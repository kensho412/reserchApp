"""Thin async client for a local Ollama server.

Only two endpoints are used: /api/chat (JSON-mode generation) and /api/embeddings.
If Ollama is unreachable the helpers raise OllamaUnavailable so the pipeline can
record a soft failure instead of crashing the request.
"""
from __future__ import annotations

import json
from typing import Any

import httpx

from . import config


class OllamaUnavailable(RuntimeError):
    pass


async def chat_json(prompt: str, *, system: str, model: str | None = None) -> dict[str, Any]:
    """Run a single-turn chat asking for JSON, return the parsed object."""
    payload = {
        "model": model or config.OLLAMA_CHAT_MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
        "stream": False,
        "format": "json",          # Ollama constrains output to valid JSON
        "options": {"temperature": 0.2},
    }
    try:
        async with httpx.AsyncClient(timeout=config.OLLAMA_TIMEOUT) as client:
            resp = await client.post(f"{config.OLLAMA_HOST}/api/chat", json=payload)
            resp.raise_for_status()
            data = resp.json()
    except (httpx.HTTPError, httpx.ConnectError) as exc:  # pragma: no cover - network
        raise OllamaUnavailable(str(exc)) from exc

    content = data.get("message", {}).get("content", "").strip()
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        # Best-effort: pull the outermost {...} block.
        start, end = content.find("{"), content.rfind("}")
        if start != -1 and end != -1 and end > start:
            return json.loads(content[start : end + 1])
        raise OllamaUnavailable(f"non-JSON LLM output: {content[:200]!r}")


async def embed(text: str, *, model: str | None = None) -> list[float]:
    payload = {"model": model or config.OLLAMA_EMBED_MODEL, "prompt": text}
    try:
        async with httpx.AsyncClient(timeout=config.OLLAMA_TIMEOUT) as client:
            resp = await client.post(f"{config.OLLAMA_HOST}/api/embeddings", json=payload)
            resp.raise_for_status()
            return resp.json()["embedding"]
    except (httpx.HTTPError, KeyError) as exc:  # pragma: no cover - network
        raise OllamaUnavailable(str(exc)) from exc


async def health() -> bool:
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{config.OLLAMA_HOST}/api/tags")
            return resp.status_code == 200
    except httpx.HTTPError:
        return False
