"""SQLite engine + session helpers and initial tag seeding."""
from __future__ import annotations

from contextlib import contextmanager
from typing import Iterator

from sqlmodel import Session, SQLModel, create_engine, select

from . import config, models
from .seed_tags import SEED_TAGS

engine = create_engine(
    config.DATABASE_URL,
    echo=False,
    connect_args={"check_same_thread": False},
)


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    _migrate()
    _seed_tags()


def _migrate() -> None:
    """Add columns introduced after a DB was first created (SQLite, additive)."""
    from sqlalchemy import text

    wanted = {"thumbnail_url": "VARCHAR"}
    with engine.begin() as conn:
        existing = {row[1] for row in conn.execute(text("PRAGMA table_info(page)"))}
        for col, coltype in wanted.items():
            if col not in existing:
                conn.execute(text(f"ALTER TABLE page ADD COLUMN {col} {coltype}"))


def _seed_tags() -> None:
    with Session(engine) as session:
        existing = {t.name for t in session.exec(select(models.Tag)).all()}
        added = False
        for name, category in SEED_TAGS:
            if name not in existing:
                session.add(models.Tag(name=name, category=category))
                added = True
        if added:
            session.commit()


@contextmanager
def get_session() -> Iterator[Session]:
    with Session(engine) as session:
        yield session


def session_dep() -> Iterator[Session]:
    """FastAPI dependency."""
    with Session(engine) as session:
        yield session
