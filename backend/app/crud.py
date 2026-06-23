"""Database helpers: tag wiring, link wiring, and model -> schema serialization."""
from __future__ import annotations

import json
from datetime import datetime, timezone

import math

from sqlmodel import Session, func, select

from . import media, models, schemas, textutils


def tag_idf(session: Session) -> dict[str, float]:
    """Inverse-document-frequency weight per tag. Tags shared by almost every
    page weigh ~0; rare tags weigh high. Used to make similarity discriminating."""
    total = len(session.exec(select(models.Page.id)).all()) or 1
    rows = session.exec(
        select(models.Tag.name, func.count(models.PageTag.page_id))
        .join(models.PageTag, models.PageTag.tag_id == models.Tag.id)
        .group_by(models.Tag.name)
    ).all()
    return {name: math.log((1 + total) / (1 + df)) for name, df in rows}


def card_thumbnail(page: models.Page) -> str | None:
    """Pick the best thumbnail for a card. Priority: video > og:image > PDF."""
    vid = media.video_thumbnail(page.video_url)
    if vid:
        return vid
    if page.thumbnail_url:
        return page.thumbnail_url
    if page.thumbnail_path:
        return f"files/{page.thumbnail_path}"      # client resolves against server URL
    return None


# --- tags --------------------------------------------------------------------
def get_or_create_tag(session: Session, name: str, category: str = "topic") -> models.Tag:
    name = name.lstrip("#").lower().strip()
    tag = session.exec(select(models.Tag).where(models.Tag.name == name)).first()
    if tag is None:
        tag = models.Tag(name=name, category=category)
        session.add(tag)
        session.flush()
    return tag


def set_page_tags(session: Session, page: models.Page, tag_names: list[str]) -> None:
    """Replace the page's tag set with exactly tag_names."""
    session.exec(
        select(models.PageTag).where(models.PageTag.page_id == page.id)
    )  # ensure table touched
    for pt in session.exec(select(models.PageTag).where(models.PageTag.page_id == page.id)).all():
        session.delete(pt)
    seen: set[str] = set()
    for raw in tag_names:
        name = raw.lstrip("#").lower().strip()
        if not name or name in seen:
            continue
        seen.add(name)
        tag = get_or_create_tag(session, name)
        session.add(models.PageTag(page_id=page.id, tag_id=tag.id))


def add_page_tags(session: Session, page: models.Page, tag_names: list[str]) -> None:
    """Add tags to a page (union); never removes existing ones."""
    existing = set(page_tag_names(session, page.id))
    for raw in tag_names:
        name = raw.lstrip("#").lower().strip()
        if not name or name in existing:
            continue
        existing.add(name)
        tag = get_or_create_tag(session, name)
        session.add(models.PageTag(page_id=page.id, tag_id=tag.id))


def page_tag_names(session: Session, page_id: str) -> list[str]:
    rows = session.exec(
        select(models.Tag.name)
        .join(models.PageTag, models.PageTag.tag_id == models.Tag.id)
        .where(models.PageTag.page_id == page_id)
    ).all()
    return sorted(rows)


# --- internal links ----------------------------------------------------------
def sync_links(session: Session, page: models.Page) -> None:
    """Rebuild [[outgoing links]] for a page from its body."""
    for link in session.exec(
        select(models.PageLink).where(models.PageLink.from_id == page.id)
    ).all():
        session.delete(link)
    for title in textutils.extract_links(page.body):
        session.add(models.PageLink(from_id=page.id, to_title=title))


def backlink_titles(session: Session, page_title: str) -> list[str]:
    rows = session.exec(
        select(models.Page.title)
        .join(models.PageLink, models.PageLink.from_id == models.Page.id)
        .where(models.PageLink.to_title == page_title)
    ).all()
    return sorted(set(rows))


# --- serialization -----------------------------------------------------------
def to_card(session: Session, page: models.Page) -> schemas.PageCard:
    return schemas.PageCard(
        id=page.id,
        title=page.title,
        type=page.type,
        tags=page_tag_names(session, page.id),
        summary_ja=page.summary_ja,
        authors=page.authors,
        year=page.year,
        thumbnail=card_thumbnail(page),
        updated_at=page.updated_at,
    )


def latest_llm(session: Session, page_id: str) -> models.LLMOutput | None:
    return session.exec(
        select(models.LLMOutput)
        .where(models.LLMOutput.page_id == page_id)
        .order_by(models.LLMOutput.created_at.desc())
    ).first()


def _llm_to_read(out: models.LLMOutput) -> schemas.LLMOutputRead:
    return schemas.LLMOutputRead(
        summary_ja=out.summary_ja,
        suggested_tags=json.loads(out.suggested_tags_json or "[]"),
        abstract_ja=out.abstract_ja,
        translation_ja=out.translation_ja,
        section_summaries=[
            schemas.SectionSummary(**s) for s in json.loads(out.section_summaries_json or "[]")
        ],
        important_quotes=json.loads(out.important_quotes_json or "[]"),
        related_candidates=json.loads(out.related_candidates_json or "[]"),
        created_at=out.created_at,
    )


def to_read(session: Session, page: models.Page) -> schemas.PageRead:
    out = latest_llm(session, page.id)
    return schemas.PageRead(
        id=page.id,
        title=page.title,
        body=page.body,
        type=page.type,
        summary_ja=page.summary_ja,
        source_url=page.source_url,
        video_url=page.video_url,
        pdf_path=page.pdf_path,
        thumbnail_path=page.thumbnail_path,
        authors=page.authors,
        year=page.year,
        tags=page_tag_names(session, page.id),
        backlinks=backlink_titles(session, page.title),
        outgoing_links=textutils.extract_links(page.body),
        related_page_ids=[],
        created_at=page.created_at,
        updated_at=page.updated_at,
        llm=_llm_to_read(out) if out else None,
    )


def touch(page: models.Page) -> None:
    page.updated_at = datetime.now(timezone.utc)
