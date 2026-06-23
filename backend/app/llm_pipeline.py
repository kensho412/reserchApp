"""End-to-end processing pipeline for a page that has a PDF or URL attached.

Steps (per the spec):
  1. extract body text + metadata
  2. LLM summary + tag candidates + concept/tech/related
  3. for papers: abstract translation (+ optional section summaries / full translation)
  4. build embedding, store in Chroma
  5. persist an LLMOutput row; fill page metadata that is still empty

The LLM never overwrites the user's body. It only fills empty metadata fields
and writes suggestions into LLMOutput, which the Mac app surfaces as
"AI Suggestions" for the user to Accept.
"""
from __future__ import annotations

import json

from sqlmodel import Session, select

from . import config, crud, extract, media, models, ollama_client, prompts
from .seed_tags import SEED_TAGS

_VOCAB = [name for name, _ in SEED_TAGS]


async def process_page(session: Session, page: models.Page, *, ex: extract.Extracted | None = None,
                       do_sections: bool = False, do_full_translation: bool = False) -> models.LLMOutput:
    """Run analysis for a page. `ex` is the freshly extracted content, if any."""
    body_text = ""
    if ex and ex.text:
        body_text = ex.text
        _fill_metadata(session, page, ex)
    elif page.extracted_text_path:
        path = config.FILES_DIR / page.extracted_text_path
        body_text = path.read_text(encoding="utf-8") if path.exists() else ""
    body_text = (body_text or page.body)[: config.MAX_LLM_INPUT_CHARS]

    out = models.LLMOutput(page_id=page.id)

    # --- 1. analysis (summary + tags + metadata) ---
    try:
        analysis = await ollama_client.chat_json(
            prompts.analyze_prompt(
                title=page.title,
                page_type=page.type,
                source_url=page.source_url,
                body_text=body_text,
                vocabulary=_VOCAB,
            ),
            system=prompts.SYSTEM_ANALYST,
        )
    except ollama_client.OllamaUnavailable:
        analysis = {}

    out.summary_ja = (analysis.get("summary_ja") or "").strip()
    suggested = [t.lstrip("#") for t in analysis.get("suggested_tags", [])][:6]
    out.suggested_tags_json = json.dumps(suggested, ensure_ascii=False)
    out.related_candidates_json = json.dumps(
        analysis.get("related_candidates", [])[:8], ensure_ascii=False
    )

    # Auto-apply the suggested tags to the page (additive, deduplicated).
    if suggested:
        crud.add_page_tags(session, page, suggested)
    # Precise venue tags from the source domain (evidence-based, e.g. #nime).
    crud.add_page_tags(session, page, media.source_venue_tags(page.source_url))

    # Fill empty page metadata (never clobber user-provided values).
    if not page.summary_ja and out.summary_ja:
        page.summary_ja = out.summary_ja
    if not page.authors and analysis.get("authors"):
        page.authors = [a for a in analysis["authors"] if a]
    if page.year is None and isinstance(analysis.get("year"), int):
        page.year = analysis["year"]
    if analysis.get("is_paper") and page.type == "note":
        page.type = "paper"

    # --- 2. paper-specific translation ---
    is_paper = bool(analysis.get("is_paper")) or page.type == "paper"
    if is_paper and body_text:
        abstract = extract.find_abstract(body_text)
        try:
            tr = await ollama_client.chat_json(
                prompts.translate_abstract_prompt(abstract_text=abstract),
                system=prompts.SYSTEM_ANALYST,
            )
            out.abstract_ja = (tr.get("abstract_ja") or "").strip()
        except ollama_client.OllamaUnavailable:
            pass

        if do_sections:
            try:
                sec = await ollama_client.chat_json(
                    prompts.section_summaries_prompt(body_text=body_text),
                    system=prompts.SYSTEM_ANALYST,
                )
                out.section_summaries_json = json.dumps(
                    sec.get("section_summaries", []), ensure_ascii=False
                )
                out.important_quotes_json = json.dumps(
                    sec.get("important_quotes", []), ensure_ascii=False
                )
            except ollama_client.OllamaUnavailable:
                pass

        if do_full_translation:
            try:
                full = await ollama_client.chat_json(
                    prompts.full_translation_prompt(body_text=body_text),
                    system=prompts.SYSTEM_ANALYST,
                )
                out.translation_ja = (full.get("translation_ja") or "").strip()
            except ollama_client.OllamaUnavailable:
                pass

    # --- 3. embedding ---
    await _embed_page(page, summary=out.summary_ja, body_text=body_text)

    crud.touch(page)
    session.add(out)
    session.add(page)
    session.commit()
    session.refresh(out)
    return out


def _fill_metadata(session: Session, page: models.Page, ex: extract.Extracted) -> None:
    if ex.text_path:
        page.extracted_text_path = ex.text_path
    if ex.thumbnail_path and not page.thumbnail_path:
        page.thumbnail_path = ex.thumbnail_path
    if ex.image_url and not page.thumbnail_url:
        page.thumbnail_url = ex.image_url
    if ex.title and (not page.title or page.title.lower() in ("untitled", "new page")):
        page.title = ex.title
    if ex.authors and not page.authors:
        page.authors = ex.authors
    if ex.year and page.year is None:
        page.year = ex.year


async def _embed_page(page: models.Page, *, summary: str, body_text: str) -> None:
    from . import vector  # local import: chroma is heavy to import

    source = " \n".join(filter(None, [page.title, summary, body_text[:2000]]))
    if not source.strip():
        return
    try:
        vec = await ollama_client.embed(source)
    except ollama_client.OllamaUnavailable:
        return
    vector.upsert(
        page.id, vec, title=page.title, page_type=page.type,
        source_text_type="summary" if summary else "title",
    )


async def reembed_existing(session: Session) -> int:
    """Utility: (re)build embeddings for all pages. Returns count embedded."""
    count = 0
    for page in session.exec(select(models.Page)).all():
        await _embed_page(page, summary=page.summary_ja, body_text=page.body)
        count += 1
    return count
