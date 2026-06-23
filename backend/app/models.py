"""SQLModel data models -> SQLite tables.

Mirrors the data model in the spec. Lists (authors, suggested tags, section
summaries, related candidates, backlinks) are stored as JSON strings via small
helper properties so the schema stays a plain SQLite database with no extra
machinery.
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


def _uuid() -> str:
    return str(uuid.uuid4())


def _now() -> datetime:
    return datetime.now(timezone.utc)


PageType = str  # paper | artwork | exhibition | video | note | other
TagCategory = str  # type | medium | method | topic | source | context


class Page(SQLModel, table=True):
    id: str = Field(default_factory=_uuid, primary_key=True)
    title: str = Field(index=True)
    body: str = ""                                   # Markdown / plain text (source of truth)
    type: PageType = Field(default="note", index=True)
    summary_ja: str = ""

    source_url: Optional[str] = None
    video_url: Optional[str] = None
    pdf_path: Optional[str] = None                   # relative to FILES_DIR
    thumbnail_path: Optional[str] = None
    extracted_text_path: Optional[str] = None        # relative to FILES_DIR

    authors_json: str = "[]"                         # JSON list[str]
    year: Optional[int] = None

    created_at: datetime = Field(default_factory=_now)
    updated_at: datetime = Field(default_factory=_now)

    # --- convenience accessors for the JSON-encoded list ---
    @property
    def authors(self) -> list[str]:
        try:
            return json.loads(self.authors_json or "[]")
        except json.JSONDecodeError:
            return []

    @authors.setter
    def authors(self, value: list[str]) -> None:
        self.authors_json = json.dumps(value or [])


class Tag(SQLModel, table=True):
    id: str = Field(default_factory=_uuid, primary_key=True)
    name: str = Field(index=True, unique=True)       # stored without leading '#'
    category: TagCategory = Field(default="topic")


class PageTag(SQLModel, table=True):
    """Many-to-many join between pages and tags."""
    page_id: str = Field(foreign_key="page.id", primary_key=True)
    tag_id: str = Field(foreign_key="tag.id", primary_key=True)


class PageLink(SQLModel, table=True):
    """[[internal link]] edges. from_id links TO to_id (a page title)."""
    from_id: str = Field(foreign_key="page.id", primary_key=True)
    to_title: str = Field(primary_key=True, index=True)


class LLMOutput(SQLModel, table=True):
    id: str = Field(default_factory=_uuid, primary_key=True)
    page_id: str = Field(foreign_key="page.id", index=True)
    summary_ja: str = ""
    suggested_tags_json: str = "[]"                  # JSON list[str]
    abstract_ja: str = ""
    translation_ja: str = ""
    section_summaries_json: str = "[]"               # JSON list[{heading, summary}]
    important_quotes_json: str = "[]"                # JSON list[str]
    related_candidates_json: str = "[]"              # JSON list[str] (page titles)
    created_at: datetime = Field(default_factory=_now)
