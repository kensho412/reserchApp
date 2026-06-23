"""Page CRUD, search, file/URL ingestion, and similar-page lookup."""
from __future__ import annotations

import uuid
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, UploadFile, File
from sqlmodel import Session, select

from .. import config, crud, extract, llm_pipeline, models, schemas, textutils
from ..database import get_session, session_dep

router = APIRouter(prefix="/pages", tags=["pages"])


@router.get("", response_model=list[schemas.PageCard])
def list_pages(
    query: str = "",
    tags: str = "",                       # comma-separated, AND semantics
    sort: str = "updated",                # updated | created | title
    session: Session = Depends(session_dep),
):
    free, query_tags = textutils.parse_search_query(query)
    required = [t.strip().lstrip("#").lower() for t in tags.split(",") if t.strip()]
    required = list(dict.fromkeys(required + query_tags))

    stmt = select(models.Page)
    if free:
        like = f"%{free}%"
        stmt = stmt.where(
            (models.Page.title.like(like))
            | (models.Page.body.like(like))
            | (models.Page.summary_ja.like(like))
        )
    pages = session.exec(stmt).all()

    # AND-filter by tags in Python (small personal dataset).
    if required:
        kept = []
        for p in pages:
            names = set(crud.page_tag_names(session, p.id))
            if all(t in names for t in required):
                kept.append(p)
        pages = kept

    if sort == "title":
        pages.sort(key=lambda p: p.title.lower())
    elif sort == "created":
        pages.sort(key=lambda p: p.created_at, reverse=True)
    else:
        pages.sort(key=lambda p: p.updated_at, reverse=True)

    return [crud.to_card(session, p) for p in pages]


@router.post("", response_model=schemas.PageRead, status_code=201)
def create_page(payload: schemas.PageCreate, session: Session = Depends(session_dep)):
    # Cosense-style: if a page with this title exists, return it instead.
    existing = session.exec(
        select(models.Page).where(models.Page.title == payload.title)
    ).first()
    if existing:
        return crud.to_read(session, existing)

    page = models.Page(title=payload.title, type=payload.type, body=payload.body)
    session.add(page)
    session.flush()
    crud.set_page_tags(session, page, textutils.extract_tags(page.body))
    crud.sync_links(session, page)
    session.commit()
    session.refresh(page)
    return crud.to_read(session, page)


@router.get("/{page_id}", response_model=schemas.PageRead)
def get_page(page_id: str, session: Session = Depends(session_dep)):
    page = session.get(models.Page, page_id)
    if not page:
        raise HTTPException(404, "page not found")
    return crud.to_read(session, page)


@router.patch("/{page_id}", response_model=schemas.PageRead)
def update_page(page_id: str, payload: schemas.PageUpdate, session: Session = Depends(session_dep)):
    page = session.get(models.Page, page_id)
    if not page:
        raise HTTPException(404, "page not found")

    data = payload.model_dump(exclude_unset=True)
    explicit_tags = data.pop("tags", None)
    authors = data.pop("authors", None)
    old_video = page.video_url
    for k, v in data.items():
        setattr(page, k, v)
    if authors is not None:
        page.authors = authors

    # Vimeo thumbnail needs an oEmbed lookup. Resolve it when the video link
    # changed, or to backfill a Vimeo page that still has no thumbnail.
    if "video_url" in data:
        from .. import media

        nv = page.video_url
        if nv and media.is_vimeo(nv) and (nv != old_video or not page.thumbnail_url):
            thumb = media.vimeo_thumbnail(nv)
            if thumb:
                page.thumbnail_url = thumb

    # Precise venue tags implied by the source URL (e.g. NIME source -> #nime).
    if "source_url" in data and page.source_url:
        from .. import media

        crud.add_page_tags(session, page, media.source_venue_tags(page.source_url))

    # Tags: an explicit set replaces everything; otherwise body #tags are added
    # (additive, so LLM-applied tags survive body edits / autosave).
    if explicit_tags is not None:
        crud.set_page_tags(session, page, explicit_tags)
    elif "body" in data:
        crud.add_page_tags(session, page, textutils.extract_tags(page.body))
    if "body" in data:
        crud.sync_links(session, page)

    crud.touch(page)
    session.add(page)
    session.commit()
    session.refresh(page)
    return crud.to_read(session, page)


@router.delete("/{page_id}", status_code=204)
def delete_page(page_id: str, session: Session = Depends(session_dep)):
    from .. import vector

    page = session.get(models.Page, page_id)
    if not page:
        raise HTTPException(404, "page not found")
    for pt in session.exec(select(models.PageTag).where(models.PageTag.page_id == page_id)).all():
        session.delete(pt)
    for pl in session.exec(select(models.PageLink).where(models.PageLink.from_id == page_id)).all():
        session.delete(pl)
    session.delete(page)
    session.commit()
    vector.delete(page_id)


# --- ingestion ---------------------------------------------------------------
def _run_pipeline(page_id: str, ex: extract.Extracted, **kw) -> None:
    """Background task: open its own session + event loop."""
    import asyncio

    with get_session() as session:
        page = session.get(models.Page, page_id)
        if page:
            asyncio.run(llm_pipeline.process_page(session, page, ex=ex, **kw))


@router.post("/{page_id}/upload_pdf", response_model=schemas.PageRead)
def upload_pdf(
    page_id: str,
    background: BackgroundTasks,
    file: UploadFile = File(...),
    session: Session = Depends(session_dep),
):
    page = session.get(models.Page, page_id)
    if not page:
        raise HTTPException(404, "page not found")

    rel = f"{uuid.uuid4()}.pdf"
    dest: Path = config.FILES_DIR / rel
    dest.write_bytes(file.file.read())
    page.pdf_path = rel
    crud.touch(page)
    session.add(page)
    session.commit()
    session.refresh(page)

    ex = extract.extract_pdf(dest)
    background.add_task(_run_pipeline, page_id, ex)
    return crud.to_read(session, page)


@router.post("/{page_id}/submit_url", response_model=schemas.PageRead)
def submit_url(
    page_id: str,
    payload: schemas.SubmitURL,
    background: BackgroundTasks,
    session: Session = Depends(session_dep),
):
    page = session.get(models.Page, page_id)
    if not page:
        raise HTTPException(404, "page not found")

    page.source_url = payload.url
    crud.touch(page)
    session.add(page)
    session.commit()
    session.refresh(page)

    ex = extract.extract_url(payload.url)
    background.add_task(_run_pipeline, page_id, ex)
    return crud.to_read(session, page)


# --- similar -----------------------------------------------------------------
# Tuning knobs. In a field where everything shares broad tags (#media-art,
# #installation), rarity-weighting + thresholds keep "Similar" meaningful.
MIN_TAG_SCORE = 0.30        # weighted shared-tag overlap required (0..1)
MIN_EMBED_SCORE = 0.62      # cosine similarity required for an embedding match


@router.get("/{page_id}/similar", response_model=list[schemas.SimilarPage])
def similar(page_id: str, session: Session = Depends(session_dep)):
    from .. import vector
    import asyncio

    page = session.get(models.Page, page_id)
    if not page:
        raise HTTPException(404, "page not found")

    results: dict[str, schemas.SimilarPage] = {}

    # 1. Same-tags, weighted by tag rarity (IDF). Sharing a rare tag (chladni)
    #    counts; sharing a ubiquitous one (media-art) barely moves the score.
    weights = crud.tag_idf(session)
    my_tags = set(crud.page_tag_names(session, page_id))
    my_weight = sum(weights.get(t, 1.0) for t in my_tags)
    if my_tags and my_weight > 0:
        for other in session.exec(select(models.Page).where(models.Page.id != page_id)).all():
            shared = my_tags & set(crud.page_tag_names(session, other.id))
            if not shared:
                continue
            score = sum(weights.get(t, 1.0) for t in shared) / my_weight
            if score >= MIN_TAG_SCORE:
                results[other.id] = schemas.SimilarPage(
                    id=other.id, title=other.title, type=other.type,
                    score=round(score, 3), reason="same-tags",
                )

    # 2. Embedding neighbours (re-embed this page's text, then ANN query),
    #    only above a similarity threshold so the whole corpus doesn't qualify.
    from .. import ollama_client

    source = " \n".join(filter(None, [page.title, page.summary_ja, page.body[:2000]]))
    if source.strip():
        try:
            vec = asyncio.run(ollama_client.embed(source))
        except Exception:
            vec = None
        if vec:
            for pid, sc in vector.query(vec, n=8, exclude_id=page_id):
                if sc < MIN_EMBED_SCORE:
                    continue
                other = session.get(models.Page, pid)
                if not other:
                    continue
                if pid in results:
                    results[pid].score = max(results[pid].score, round(sc, 3))
                else:
                    results[pid] = schemas.SimilarPage(
                        id=pid, title=other.title, type=other.type,
                        score=round(sc, 3), reason="embedding",
                    )

    return sorted(results.values(), key=lambda s: s.score, reverse=True)[:10]
