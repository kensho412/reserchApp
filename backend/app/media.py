"""Derive thumbnail image URLs from video links (no network calls)."""
from __future__ import annotations

from urllib.parse import parse_qs, urlparse


def youtube_id(url: str) -> str | None:
    try:
        p = urlparse(url)
    except ValueError:
        return None
    host = (p.hostname or "").lower()
    if "youtu.be" in host:
        return p.path.lstrip("/").split("/")[0] or None
    if "youtube.com" in host:
        if p.path.startswith("/embed/"):
            return p.path.split("/")[2] if len(p.path.split("/")) > 2 else None
        vid = parse_qs(p.query).get("v", [None])[0]
        return vid
    return None


def video_thumbnail(url: str | None) -> str | None:
    """Best-effort thumbnail URL for a video link. YouTube only (Google CDN);
    Vimeo and others rely on the source page's og:image instead."""
    if not url:
        return None
    yid = youtube_id(url)
    if yid:
        return f"https://img.youtube.com/vi/{yid}/hqdefault.jpg"
    return None
