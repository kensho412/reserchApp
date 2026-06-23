"""FastAPI entrypoint for the Research Atlas backend.

Run with:  uvicorn app.main:app --host 0.0.0.0 --port 8000
Bind to 0.0.0.0 only on a Tailscale-protected machine; never port-forward it.
"""
from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from . import config
from .database import init_db
from .ollama_client import health
from .routers import llm, pages, tags

app = FastAPI(title="Research Atlas", version="0.1.0")

# SwiftUI app is a native client; CORS is permissive for local/Tailscale use.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(pages.router)
app.include_router(tags.router)
app.include_router(llm.router)

# Serve stored PDFs / thumbnails / extracted text at /files/<relpath>.
app.mount("/files", StaticFiles(directory=str(config.FILES_DIR)), name="files")


@app.on_event("startup")
def _startup() -> None:
    init_db()


@app.get("/health")
async def health_check():
    return {"status": "ok", "ollama": await health()}
