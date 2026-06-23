"""Text + metadata extraction from PDFs and web pages, plus thumbnailing.

PDF: PyMuPDF (fitz). Web: trafilatura. Both are pure-local / OSS.
"""
from __future__ import annotations

import re
import uuid
from dataclasses import dataclass, field
from pathlib import Path

import fitz  # PyMuPDF
import httpx
import trafilatura

from . import config


@dataclass
class Extracted:
    text: str = ""
    title: str = ""
    authors: list[str] = field(default_factory=list)
    year: int | None = None
    thumbnail_path: str | None = None      # relative to FILES_DIR
    text_path: str | None = None           # relative to FILES_DIR


def _save_text(text: str) -> str:
    name = f"{uuid.uuid4()}.txt"
    (config.FILES_DIR / name).write_text(text, encoding="utf-8")
    return name


def extract_pdf(pdf_abs_path: Path) -> Extracted:
    doc = fitz.open(pdf_abs_path)
    parts = [page.get_text("text") for page in doc]
    text = "\n".join(parts).strip()

    meta = doc.metadata or {}
    title = (meta.get("title") or "").strip()
    authors = [a.strip() for a in re.split(r"[;,]", meta.get("author") or "") if a.strip()]

    # Render first page as a thumbnail.
    thumb_rel = None
    if doc.page_count:
        pix = doc[0].get_pixmap(matrix=fitz.Matrix(0.6, 0.6))
        thumb_rel = f"{uuid.uuid4()}.png"
        pix.save(config.FILES_DIR / thumb_rel)
    doc.close()

    year = _guess_year(text)
    return Extracted(
        text=text,
        title=title or _guess_title(text),
        authors=authors,
        year=year,
        thumbnail_path=thumb_rel,
        text_path=_save_text(text) if text else None,
    )


def extract_url(url: str) -> Extracted:
    downloaded = trafilatura.fetch_url(url)
    if not downloaded:
        # Fallback to a plain GET (some servers reject trafilatura's UA).
        with httpx.Client(timeout=30, follow_redirects=True) as client:
            downloaded = client.get(url).text

    text = trafilatura.extract(downloaded, include_comments=False, favor_recall=True) or ""
    meta = trafilatura.extract_metadata(downloaded)
    title = (meta.title if meta and meta.title else "").strip()
    authors: list[str] = []
    if meta and meta.author:
        authors = [a.strip() for a in re.split(r"[;,]", meta.author) if a.strip()]
    year = None
    if meta and meta.date:
        m = re.search(r"(19|20)\d{2}", meta.date)
        if m:
            year = int(m.group(0))

    return Extracted(
        text=text.strip(),
        title=title or _guess_title(text),
        authors=authors,
        year=year or _guess_year(text),
        text_path=_save_text(text) if text else None,
    )


def find_abstract(text: str) -> str:
    """Best-effort abstract slice for papers."""
    m = re.search(r"\babstract\b", text, re.IGNORECASE)
    if not m:
        return text[:1500]
    tail = text[m.end():]
    # Cut at the next likely section heading.
    stop = re.search(r"\n\s*(1\.?\s+introduction|introduction|keywords)\b", tail, re.IGNORECASE)
    return (tail[: stop.start()] if stop else tail[:1800]).strip(" :\n")


def _guess_title(text: str) -> str:
    for line in (text or "").splitlines():
        line = line.strip()
        if len(line) > 8:
            return line[:140]
    return "Untitled"


def _guess_year(text: str) -> int | None:
    years = [int(y) for y in re.findall(r"(?:19|20)\d{2}", text or "")]
    plausible = [y for y in years if 1950 <= y <= 2035]
    return max(set(plausible), key=plausible.count) if plausible else None
