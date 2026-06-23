"""Pydantic request/response schemas for the API layer."""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class PageCreate(BaseModel):
    title: str
    type: str = "note"
    body: str = ""


class PageUpdate(BaseModel):
    title: Optional[str] = None
    body: Optional[str] = None
    type: Optional[str] = None
    summary_ja: Optional[str] = None
    source_url: Optional[str] = None
    video_url: Optional[str] = None
    authors: Optional[list[str]] = None
    year: Optional[int] = None
    tags: Optional[list[str]] = None          # full replacement set (without '#')


class SubmitURL(BaseModel):
    url: str


class TagRead(BaseModel):
    name: str
    category: str
    count: int = 0


class SectionSummary(BaseModel):
    heading: str
    summary: str


class LLMOutputRead(BaseModel):
    summary_ja: str = ""
    suggested_tags: list[str] = []
    abstract_ja: str = ""
    translation_ja: str = ""
    section_summaries: list[SectionSummary] = []
    important_quotes: list[str] = []
    related_candidates: list[str] = []
    created_at: Optional[datetime] = None


class PageCard(BaseModel):
    """Compact form used by the Home list."""
    id: str
    title: str
    type: str
    tags: list[str] = []
    summary_ja: str = ""
    authors: list[str] = []
    year: Optional[int] = None
    # Best display thumbnail: absolute http(s) URL (video / og:image) or a
    # "files/<name>" path the client resolves against its server URL. None = none.
    thumbnail: Optional[str] = None
    updated_at: datetime


class PageRead(BaseModel):
    id: str
    title: str
    body: str
    type: str
    summary_ja: str = ""
    source_url: Optional[str] = None
    video_url: Optional[str] = None
    pdf_path: Optional[str] = None
    thumbnail_path: Optional[str] = None
    authors: list[str] = []
    year: Optional[int] = None
    tags: list[str] = []
    backlinks: list[str] = []                 # titles of pages linking here
    outgoing_links: list[str] = []            # [[titles]] referenced in body
    related_page_ids: list[str] = []
    created_at: datetime
    updated_at: datetime
    llm: Optional[LLMOutputRead] = None


class SimilarPage(BaseModel):
    id: str
    title: str
    type: str
    score: float                              # higher = more similar
    reason: str                               # "same-tags" | "embedding"
