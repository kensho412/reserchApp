"""Initial tag vocabulary (name, category). Names stored without leading '#'.

Categories: type | medium | method | topic | source | context
"""
from __future__ import annotations

SEED_TAGS: list[tuple[str, str]] = [
    # 形式・媒体 (type / medium)
    ("paper", "type"), ("artwork", "type"), ("performance", "medium"),
    ("installation", "medium"), ("audiovisual", "medium"), ("sound-art", "medium"),
    ("instrument", "medium"), ("interface", "medium"), ("composition", "medium"),
    ("interactive", "method"), ("lecture-performance", "medium"), ("web", "medium"),
    ("video", "medium"), ("object", "medium"),
    # 音・音楽 (topic)
    ("experimental-music", "topic"), ("x-music", "topic"), ("sound-synthesis", "method"),
    ("modal-synthesis", "method"), ("field-recording", "method"), ("feedback", "topic"),
    ("resonance", "topic"), ("rhythm", "topic"), ("spatial-audio", "topic"),
    ("sonification", "method"), ("audification", "method"),
    # 映像・視覚 (topic)
    ("visual-music", "topic"), ("generative-visuals", "method"), ("projection", "medium"),
    ("light", "topic"), ("camera", "method"), ("computer-vision", "method"),
    ("image-to-sound", "method"), ("sound-to-image", "method"), ("visualization", "method"),
    # 身体・演奏 (topic)
    ("gesture", "topic"), ("embodiment", "topic"), ("performer", "topic"),
    ("motion", "topic"), ("dance", "topic"), ("kinetic", "topic"),
    ("physical-interface", "method"), ("augmented-instrument", "medium"),
    # 物理・素材 (topic)
    ("vibration", "topic"), ("acoustics", "topic"), ("chladni", "topic"),
    ("resonator", "topic"), ("materiality", "topic"), ("mechanical", "topic"),
    ("robotics", "method"), ("fluid", "topic"), ("light-material", "topic"),
    ("fabrication", "method"), ("3d-printing", "method"),
    # 計算・システム (method)
    ("generative", "method"), ("algorithmic", "method"), ("simulation", "method"),
    ("agent-based", "method"), ("machine-learning", "method"), ("llm", "method"),
    ("sensor", "method"), ("real-time", "method"), ("networked", "method"),
    ("database", "method"),
    # 関係性・構造 (topic)
    ("feedback-system", "topic"), ("translation", "method"), ("mapping", "method"),
    ("cross-modal", "topic"), ("synesthesia", "topic"), ("mutation", "topic"),
    ("hybrid", "topic"), ("chimera", "topic"), ("autonomous-system", "topic"),
    ("human-machine", "topic"), ("environmental", "topic"),
    # 展示・研究文脈 (source / context)
    ("nime", "source"), ("media-art", "context"), ("icc", "source"),
    ("ycam", "source"), ("iamas", "source"), ("geidai", "source"),
    ("academic-paper", "context"), ("case-study", "context"), ("reference", "context"),
    ("precedent", "context"),
]
