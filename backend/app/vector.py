"""Chroma vector store wrapper for embedding-based similar-page search.

Vectors come from Ollama's embedding model (we pass embeddings in directly, so
Chroma is used purely as a persistent ANN index — no embedding API calls).
"""
from __future__ import annotations

import chromadb

from . import config

_client = chromadb.PersistentClient(path=str(config.CHROMA_DIR))
_collection = _client.get_or_create_collection(
    name="pages",
    metadata={"hnsw:space": "cosine"},
)


def upsert(page_id: str, vector: list[float], *, title: str, page_type: str, source_text_type: str) -> None:
    _collection.upsert(
        ids=[page_id],
        embeddings=[vector],
        metadatas=[{"title": title, "type": page_type, "source_text_type": source_text_type}],
    )


def query(vector: list[float], *, n: int = 8, exclude_id: str | None = None) -> list[tuple[str, float]]:
    """Return [(page_id, score)] where score in [0,1], higher = more similar."""
    res = _collection.query(query_embeddings=[vector], n_results=n + (1 if exclude_id else 0))
    ids = res.get("ids", [[]])[0]
    dists = res.get("distances", [[]])[0]
    out: list[tuple[str, float]] = []
    for pid, dist in zip(ids, dists):
        if pid == exclude_id:
            continue
        out.append((pid, 1.0 - float(dist)))      # cosine distance -> similarity
    return out[:n]


def delete(page_id: str) -> None:
    try:
        _collection.delete(ids=[page_id])
    except Exception:  # pragma: no cover - best effort
        pass
