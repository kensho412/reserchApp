"""Tag listing and tag -> pages lookup."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, func, select

from .. import crud, models, schemas
from ..database import session_dep

router = APIRouter(prefix="/tags", tags=["tags"])


@router.get("", response_model=list[schemas.TagRead])
def list_tags(only_used: bool = False, session: Session = Depends(session_dep)):
    counts = dict(
        session.exec(
            select(models.PageTag.tag_id, func.count(models.PageTag.page_id))
            .group_by(models.PageTag.tag_id)
        ).all()
    )
    out: list[schemas.TagRead] = []
    for tag in session.exec(select(models.Tag).order_by(models.Tag.name)).all():
        c = counts.get(tag.id, 0)
        if only_used and c == 0:
            continue
        out.append(schemas.TagRead(name=tag.name, category=tag.category, count=c))
    # Most-used first, then alphabetical.
    out.sort(key=lambda t: (-t.count, t.name))
    return out


@router.get("/{tag}/pages", response_model=list[schemas.PageCard])
def pages_for_tag(tag: str, session: Session = Depends(session_dep)):
    name = tag.lstrip("#").lower()
    tag_row = session.exec(select(models.Tag).where(models.Tag.name == name)).first()
    if not tag_row:
        raise HTTPException(404, "tag not found")
    page_ids = session.exec(
        select(models.PageTag.page_id).where(models.PageTag.tag_id == tag_row.id)
    ).all()
    pages = [session.get(models.Page, pid) for pid in page_ids]
    pages = [p for p in pages if p]
    pages.sort(key=lambda p: p.updated_at, reverse=True)
    return [crud.to_card(session, p) for p in pages]
