"""Derive thumbnail image URLs from video links.

YouTube thumbnails are computed offline from the id. Vimeo has no predictable
thumbnail URL, so we resolve it once via Vimeo's free, key-less oEmbed endpoint.
"""
from __future__ import annotations

import re
from urllib.parse import parse_qs, urlparse

import httpx


# Source domain -> precise venue tag. Evidence-based: the page's source_url
# actually points at the venue, so the tag means something specific (e.g. #nime
# == accepted at / published by NIME), not an LLM guess.
_VENUE_DOMAINS: dict[str, str] = {
    "ntticc.or.jp": "icc",
    "ycam.jp": "ycam",
    "iamas.ac.jp": "iamas",
    "geidai.ac.jp": "geidai",
    "ars.electronica.art": "media-art",
    "zkm.de": "media-art",
}

# NIME uses a different domain every year: nime.org, nime2024.org, nime2025.org…
# plus the PubPub proceedings host.
_NIME_HOST_RE = re.compile(r"^(nime\d{2,4}|nime)\.org$")


def source_venue_tags(url: str | None) -> list[str]:
    """Precise tags implied by the source URL's domain (venue evidence)."""
    if not url:
        return []
    try:
        host = (urlparse(url).hostname or "").lower()
    except ValueError:
        return []
    if host.startswith("www."):
        host = host[4:]
    tags: list[str] = []
    if _NIME_HOST_RE.match(host) or host == "nime.pubpub.org" or host.endswith(".nime.org"):
        tags.append("nime")
    for domain, tag in _VENUE_DOMAINS.items():
        if host == domain or host.endswith("." + domain):
            if tag not in tags:
                tags.append(tag)
    return tags


def content_venue_tags(text: str | None) -> list[str]:
    """Venue tags inferred from a document's own text (evidence in the content).

    NIME papers carry the conference byline (e.g. "NIME'18, June 3-6, 2018, …")
    and the proceedings title. PDF extraction often breaks phrases across lines,
    so match whitespace-tolerantly. The byline is a strong single signal; the
    proceedings title needs several hits so a lone citation doesn't trigger it.
    """
    if not text:
        return []
    tags: list[str] = []
    byline = re.search(r"NIME\s*['’]\s*\d{2}", text)            # NIME'18 / NIME ’23
    phrase = len(re.findall(r"New\s+Interfaces\s+for\s+Musical\s+Expression", text, re.IGNORECASE))
    if byline or phrase >= 3:
        tags.append("nime")
    return tags


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
    """Offline thumbnail URL for a video link (no network). YouTube only."""
    if not url:
        return None
    yid = youtube_id(url)
    if yid:
        return f"https://img.youtube.com/vi/{yid}/hqdefault.jpg"
    return None


def vimeo_id(url: str) -> str | None:
    try:
        p = urlparse(url)
    except ValueError:
        return None
    if "vimeo.com" not in (p.hostname or "").lower():
        return None
    parts = [seg for seg in p.path.split("/") if seg]
    for seg in reversed(parts):              # handles vimeo.com/<id> and player.vimeo.com/video/<id>
        if seg.isdigit():
            return seg
    return None


def is_vimeo(url: str | None) -> bool:
    return bool(url) and vimeo_id(url) is not None


def vimeo_thumbnail(url: str | None) -> str | None:
    """Resolve a Vimeo thumbnail via the free oEmbed endpoint (one network call)."""
    vid = vimeo_id(url or "")
    if not vid:
        return None
    try:
        r = httpx.get(
            "https://vimeo.com/api/oembed.json",
            params={"url": f"https://vimeo.com/{vid}"},
            timeout=5,
            follow_redirects=True,
        )
        if r.status_code == 200:
            return r.json().get("thumbnail_url") or None
    except (httpx.HTTPError, ValueError):
        return None
    return None
