"""Manual LLM triggers: re-analyze and translate."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session

from .. import crud, llm_pipeline, models, ollama_client, schemas
from ..database import session_dep

router = APIRouter(prefix="/pages/{page_id}/llm", tags=["llm"])


@router.post("/analyze", response_model=schemas.LLMOutputRead)
async def analyze(page_id: str, session: Session = Depends(session_dep)):
    page = session.get(models.Page, page_id)
    if not page:
        raise HTTPException(404, "page not found")
    out = await llm_pipeline.process_page(session, page)
    return crud._llm_to_read(out)


@router.post("/translate", response_model=schemas.LLMOutputRead)
async def translate(
    page_id: str,
    sections: bool = True,
    full: bool = False,
    session: Session = Depends(session_dep),
):
    page = session.get(models.Page, page_id)
    if not page:
        raise HTTPException(404, "page not found")
    out = await llm_pipeline.process_page(
        session, page, do_sections=sections, do_full_translation=full
    )
    return crud._llm_to_read(out)


@router.get("/health")
async def llm_health():
    return {"ollama": await ollama_client.health()}
