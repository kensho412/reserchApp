"""Lightweight, compiler-free vector store for embedding similarity search.

Chroma/hnswlib need a native C++ toolchain (fails to build on Windows without
MS Visual C++ Build Tools). For a personal-scale atlas a brute-force cosine
search over a few thousand vectors is effectively instant, so we keep vectors
in memory and persist them as a single pickle next to the SQLite DB. Only
`numpy` is required, which ships prebuilt wheels everywhere.

Public API is unchanged: upsert / query / delete.
"""
from __future__ import annotations

import pickle
import threading

import numpy as np

from . import config

_STORE_PATH = config.DATA_DIR / "vectors.pkl"
_lock = threading.Lock()


def _load() -> dict:
    if _STORE_PATH.exists():
        try:
            with open(_STORE_PATH, "rb") as f:
                return pickle.load(f)
        except Exception:  # pragma: no cover - corrupt store -> start fresh
            return {}
    return {}


# page_id -> {"vec": np.ndarray (L2-normalized), "title", "type", "source_text_type"}
_store: dict = _load()


def _save() -> None:
    tmp = _STORE_PATH.with_suffix(".pkl.tmp")
    with open(tmp, "wb") as f:
        pickle.dump(_store, f)
    tmp.replace(_STORE_PATH)


def _normalize(vector) -> np.ndarray:
    vec = np.asarray(vector, dtype=np.float32)
    norm = float(np.linalg.norm(vec))
    return vec / norm if norm > 0 else vec


def upsert(page_id: str, vector: list[float], *, title: str, page_type: str,
           source_text_type: str) -> None:
    with _lock:
        _store[page_id] = {
            "vec": _normalize(vector),
            "title": title,
            "type": page_type,
            "source_text_type": source_text_type,
        }
        _save()


def query(vector: list[float], *, n: int = 8, exclude_id: str | None = None) -> list[tuple[str, float]]:
    """Return [(page_id, score)] with score in [0,1] (higher = more similar)."""
    q = _normalize(vector)
    if not np.any(q):
        return []
    with _lock:
        items = [(pid, d["vec"]) for pid, d in _store.items() if pid != exclude_id]
    # Cosine similarity == dot product since everything is L2-normalized.
    scored = [(pid, float(np.dot(q, vec))) for pid, vec in items]
    scored.sort(key=lambda x: x[1], reverse=True)
    return scored[:n]


def delete(page_id: str) -> None:
    with _lock:
        if page_id in _store:
            del _store[page_id]
            _save()
