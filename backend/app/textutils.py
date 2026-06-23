"""Parsing helpers for #tags and [[internal links]] inside page bodies."""
from __future__ import annotations

import re

# A tag: '#' followed by letters/digits/hyphen. Hyphen allowed mid-token.
_TAG_RE = re.compile(r"(?<!\w)#([a-zA-Z0-9][a-zA-Z0-9\-]*)")
# An internal link: [[Page Title]]
_LINK_RE = re.compile(r"\[\[([^\[\]]+?)\]\]")


def extract_tags(text: str) -> list[str]:
    """Return unique tag names (without '#'), preserving first-seen order."""
    seen: dict[str, None] = {}
    for m in _TAG_RE.finditer(text or ""):
        seen.setdefault(m.group(1).lower(), None)
    return list(seen)


def extract_links(text: str) -> list[str]:
    """Return unique [[internal link]] titles, preserving order."""
    seen: dict[str, None] = {}
    for m in _LINK_RE.finditer(text or ""):
        seen.setdefault(m.group(1).strip(), None)
    return list(seen)


def parse_search_query(q: str) -> tuple[str, list[str]]:
    """Split a Cosense-style query into (free_text, required_tags).

    Example: 'chladni #installation #instrument'
      -> ('chladni', ['installation', 'instrument'])
    """
    tags = extract_tags(q)
    free = _TAG_RE.sub("", q or "").strip()
    free = re.sub(r"\s+", " ", free)
    return free, tags
