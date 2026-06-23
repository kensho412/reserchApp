"""LLM prompts. All outputs are requested as strict JSON so they parse reliably.

The model is asked to choose tags from the controlled vocabulary where possible
but may suggest a few new ones. Japanese is the target language for summaries
and translations.
"""
from __future__ import annotations

import json

SYSTEM_ANALYST = (
    "You are a research librarian for a media-art / NIME / experimental-music "
    "reference atlas. You read papers, artwork pages and exhibition records and "
    "produce concise, accurate metadata. You never invent facts that are not in "
    "the source text. You always answer with a single valid JSON object and no "
    "prose outside it."
)


def analyze_prompt(
    *,
    title: str,
    page_type: str,
    source_url: str | None,
    body_text: str,
    vocabulary: list[str],
) -> str:
    """Summary + tag-candidate + metadata extraction in one call."""
    vocab = ", ".join(f"#{t}" for t in vocabulary)
    schema = {
        "summary_ja": "1〜3文の日本語要約 (string)",
        "suggested_tags": ["controlled-vocab か新規タグ (string, '#'なし)"],
        "authors": ["著者名 (string)"],
        "year": "出版/制作年 (integer or null)",
        "concept": "作品/論文の核となるコンセプト 日本語1〜2文 (string)",
        "technologies": ["使用技術・手法 (string)"],
        "related_candidates": ["関連しそうなページ名/概念 (string)"],
        "is_paper": "学術論文なら true (boolean)",
    }
    return f"""次の資料を解析し、JSONで返してください。

# タイトル
{title}

# 種別ヒント
{page_type}

# 出典URL
{source_url or "(なし)"}

# 本文抜粋
\"\"\"
{body_text}
\"\"\"

# タグ語彙 (可能な限りここから選ぶ。なければ新規可。最大6個)
{vocab}

# 出力JSONスキーマ
{json.dumps(schema, ensure_ascii=False, indent=2)}

JSONオブジェクトのみを出力してください。"""


def translate_abstract_prompt(*, abstract_text: str) -> str:
    schema = {"abstract_ja": "アブストラクトの自然な日本語訳 (string)"}
    return f"""次の英語アブストラクトを自然で正確な日本語に翻訳してください。

\"\"\"
{abstract_text}
\"\"\"

# 出力JSONスキーマ
{json.dumps(schema, ensure_ascii=False)}

JSONオブジェクトのみを出力してください。"""


def section_summaries_prompt(*, body_text: str) -> str:
    schema = {
        "section_summaries": [{"heading": "章タイトル", "summary": "日本語要約2〜4文"}],
        "important_quotes": ["重要な引用 原文ママ (string)"],
    }
    return f"""次の論文本文を章ごとに日本語で要約し、重要な引用を抜き出してください。

\"\"\"
{body_text}
\"\"\"

# 出力JSONスキーマ
{json.dumps(schema, ensure_ascii=False, indent=2)}

JSONオブジェクトのみを出力してください。"""


def full_translation_prompt(*, body_text: str) -> str:
    schema = {"translation_ja": "全文の日本語訳 (string, Markdown可)"}
    return f"""次の英語本文を全文、自然な日本語に翻訳してください。見出し構造は保ってください。

\"\"\"
{body_text}
\"\"\"

# 出力JSONスキーマ
{json.dumps(schema, ensure_ascii=False)}

JSONオブジェクトのみを出力してください。"""
