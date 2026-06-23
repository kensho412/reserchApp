"""Central configuration. All values overridable via environment variables.

Everything is local by default. No external paid APIs are used.
"""
from __future__ import annotations

import os
from pathlib import Path

# --- Paths -------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent.parent          # backend/
DATA_DIR = Path(os.getenv("ATLAS_DATA_DIR", BASE_DIR / "data"))
FILES_DIR = DATA_DIR / "files"                             # PDFs / thumbnails / extracted text
DB_PATH = DATA_DIR / "atlas.db"
# Embedding vectors persist as DATA_DIR/vectors.pkl (see vector.py).

for _p in (DATA_DIR, FILES_DIR):
    _p.mkdir(parents=True, exist_ok=True)

DATABASE_URL = os.getenv("ATLAS_DATABASE_URL", f"sqlite:///{DB_PATH}")

# --- Ollama ------------------------------------------------------------------
# Local LLM server. On the desktop server this stays bound to localhost and is
# reached from the Mac over Tailscale; never expose Ollama to the open internet.
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://127.0.0.1:11434")
# A small, fast general model is a good default for summaries / tags / translation.
OLLAMA_CHAT_MODEL = os.getenv("OLLAMA_CHAT_MODEL", "qwen2.5:7b")
# Dedicated embedding model.
OLLAMA_EMBED_MODEL = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")

OLLAMA_TIMEOUT = float(os.getenv("OLLAMA_TIMEOUT", "600"))

# --- LLM behaviour -----------------------------------------------------------
# Max characters of extracted body text fed to the LLM for summarisation.
MAX_LLM_INPUT_CHARS = int(os.getenv("ATLAS_MAX_LLM_INPUT_CHARS", "12000"))
