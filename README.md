# Research Atlas — LLM付き Cosense風 制作リサーチ・アトラス

メディアアート / NIME / 実験音楽の **先行事例アトラス**。論文・作品ページ・展示記録・動画リンク・PDF を蓄積し、ローカル LLM (Ollama) が裏側で **要約・タグ候補・日本語訳・関連ページ候補** を生成する。操作感は Cosense 風（検索バー中心・カード一覧・`#tag`・`[[内部リンク]]`）。

**すべてローカル / 無料 / OSS。** 有料クラウド LLM（OpenAI / Claude API 等）は一切使わない。LLM は Ollama、DB は SQLite、ベクトル検索は Chroma、すべて手元で動く。

```
Mac App (SwiftUI)
   │  Tailscale
FastAPI Server
   │
Ollama  +  SQLite  +  Chroma  +  File Storage
```

---

## ディレクトリ構成

```
reserchApp/
├── backend/                 FastAPI + Ollama + SQLite + Chroma
│   ├── app/
│   │   ├── main.py          アプリ本体・ルーター登録・静的ファイル配信
│   │   ├── config.py        パス / Ollama / モデル名（環境変数で上書き可）
│   │   ├── models.py        SQLModel テーブル定義
│   │   ├── database.py      エンジン・初期化・タグ seeding
│   │   ├── seed_tags.py     初期タグ語彙（カテゴリ付き）
│   │   ├── schemas.py       API 入出力スキーマ
│   │   ├── crud.py          タグ/リンク配線・モデル→スキーマ変換
│   │   ├── textutils.py     #tag / [[link]] 抽出・検索クエリ解析
│   │   ├── extract.py       PDF(PyMuPDF) / URL(trafilatura) 抽出・サムネイル
│   │   ├── ollama_client.py Ollama /api/chat (JSON) ・/api/embeddings
│   │   ├── prompts.py       要約・タグ・翻訳のプロンプト
│   │   ├── llm_pipeline.py  抽出→LLM→DB→ベクトルの処理パイプライン
│   │   ├── vector.py        Chroma ラッパ（embedding 類似検索）
│   │   └── routers/         pages / tags / llm
│   ├── requirements.txt
│   └── run.sh               起動スクリプト
└── macapp/                  SwiftUI Mac アプリ（SwiftPM）
    ├── Package.swift
    └── Sources/ResearchAtlas/
        ├── ResearchAtlasApp.swift   App エントリ・設定シート
        ├── Models/Models.swift      API と対応する Codable 型
        ├── Services/APIClient.swift  通信
        ├── Services/AppState.swift   状態・検索・ページ作成フロー
        └── Views/  Theme / HomeView / PageDetailView / SidebarView
```

---

## セットアップ

### 1. Ollama（ローカル LLM）

```bash
brew install ollama          # または https://ollama.com からダウンロード
ollama serve                 # 別ターミナルで常駐（http://127.0.0.1:11434）

# モデルを取得（デフォルト設定に合わせる）
ollama pull qwen2.5:7b       # 要約・タグ・翻訳用（日本語に強い汎用モデル）
ollama pull nomic-embed-text # embedding 用
```

別モデルを使う場合は環境変数で上書き：
`OLLAMA_CHAT_MODEL=llama3.1:8b`、`OLLAMA_EMBED_MODEL=mxbai-embed-large` など。

> Ollama が起動していなくてもバックエンドは動く（要約・翻訳・類似検索が空になるだけ）。

### 2. バックエンド（FastAPI）

```bash
cd backend
./run.sh                     # 初回は venv 作成 + 依存インストール → uvicorn 起動
# → http://127.0.0.1:8000  （/docs に Swagger UI）
```

Python は **3.12** を想定（PyMuPDF / Chroma のwheel都合。3.14 はまだ未対応）。
`run.sh` は `python3.12` を呼ぶ。手動なら：

```bash
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

### 3. Mac アプリ（SwiftUI）

```bash
cd macapp
swift run                    # ビルドして起動（Xcode 不要）
```

または `open Package.swift` で Xcode で開いて Run。
アプリ右上の歯車から **Server URL** を設定（ローカルは `http://127.0.0.1:8000`）。

---

## 使い方（Cosense フロー）

1. **検索バーにページ名を入力** → Enter。
   既存ページがあれば開き、なければ新規作成。
2. 空ページの **source 欄に URL を貼って Enter**、または **PDF を本文にドラッグ&ドロップ**。
3. バックエンドで抽出 → Ollama が要約・タグ候補・（論文なら）翻訳を生成。
4. 結果は **AI Suggestions** として表示。`Accept` で本文に挿入される。
   - **LLM は本文を勝手に書き換えない。** 候補提示が基本。
5. 本文に `#tag` や `[[ページ名]]` を書くと自動で抽出・リンクされる。

### 検索構文

```
chladni #installation #instrument
```

→ title/body/summary に `chladni` を含み、かつ `#installation` と `#instrument`
**両方**を持つページ（タグは AND）。タグをクリックすると検索欄にトグル追加され、
`clear filter` で解除。

---

## API（FastAPI）

| Method | Path | 説明 |
|---|---|---|
| GET | `/pages?query=&tags=&sort=` | ページ一覧（検索・AND タグ絞り込み） |
| POST | `/pages` | タイトルから新規作成（同名は既存を返す） |
| GET | `/pages/{id}` | ページ詳細（tags / backlinks / llm 含む） |
| PATCH | `/pages/{id}` | body/title/type/tags 等を更新 |
| DELETE | `/pages/{id}` | 削除（ベクトルも削除） |
| POST | `/pages/{id}/upload_pdf` | PDF アップロード → 抽出 + LLM をバックグラウンド実行 |
| POST | `/pages/{id}/submit_url` | URL 登録 → 本文抽出 + LLM をバックグラウンド実行 |
| GET | `/pages/{id}/similar` | 同一タグ + embedding 類似ページ |
| POST | `/pages/{id}/llm/analyze` | LLM 解析を手動再実行 |
| POST | `/pages/{id}/llm/translate?sections=&full=` | 論文翻訳（章ごと / 全文） |
| GET | `/tags?only_used=` | タグ一覧（使用数付き） |
| GET | `/tags/{tag}/pages` | そのタグを持つページ |
| GET | `/files/{path}` | 保存済み PDF / サムネイル / 抽出テキスト |
| GET | `/health` | 稼働・Ollama 接続確認 |

PDF / URL 取り込みは即座に 200 を返し、解析はバックグラウンドで進む。
Mac アプリは取得結果を数秒間ポーリングして反映する。

---

## LLM 処理パイプライン（`llm_pipeline.py`）

1. PDF / URL から本文 + メタデータ（title / author / year）を抽出
2. 要約 + タグ候補 + concept / technologies / related を 1 回の JSON 出力で生成
3. 論文（`is_paper`）なら abstract を日本語訳（オプションで章要約・全文翻訳）
4. embedding を作成し Chroma に upsert
5. `LLMOutput` を保存。**空のメタデータだけを補完**し、ユーザーの本文は触らない

Ollama は `format: "json"` で呼び出し、出力を確実にパースする。
Ollama 不通時は `OllamaUnavailable` を握りつぶし、空の結果でソフトに失敗する。

---

## デプロイ（自宅デスクトップ + Tailscale）

1. 自宅デスクトップに Ollama とこのバックエンドを置く。
2. 起動（Tailscale 経由のみ到達可能）：
   - macOS / Linux: `HOST=0.0.0.0 ./run.sh`
   - **Windows: `./run.ps1 -BindAll`**（PowerShell）
3. Mac アプリの Server URL に Tailscale IP を設定：`http://100.x.x.x:8000`。

> **Windows デスクトップを LLM サーバにする詳細手順は [WINDOWS_SETUP.md](WINDOWS_SETUP.md)。**
> Ollama インストール、Python 3.12、ファイアウォール許可、Mac 側設定まで順番にまとめてある。

**セキュリティ**
- Ollama API（11434）を直接インターネットに公開しない。
- ルーターのポート開放はしない。
- 必ず Tailscale 経由にする。バックエンドの `0.0.0.0` バインドも Tailscale 前提。

---

## MVP の範囲と今後

**実装済み（MVP）**: HomeView / 検索バー / ページ作成 / カード一覧 / タグ一覧・AND 絞り込み /
PageDetailView 本文編集 / `#tag`・`[[link]]` 抽出 / URL 貼り付け / PDF D&D /
FastAPI 連携 / Ollama 要約・タグ候補 / 論文 Abstract 日本語訳 / SQLite + Chroma 保存。

**後回し**: 全文翻訳の作り込み / 動画埋め込み / BibTeX 出力 / グラフビュー /
類似度マップ / 高度な引用管理 / Zotero 連携。

---

## トラブルシュート

- **タグが 0 件 / DB エラー**: 初回起動時にテーブル作成 + タグ seeding が走る。`backend/data/atlas.db` を消せば再生成。
- **要約・翻訳が空**: `ollama serve` が動いているか、モデルを `pull` 済みか確認（`GET /health` の `ollama: true`）。
- **Swift アプリにフォーカスが来ない**: `swift run` 起動はバンドル無しのため、`AppDelegate` が activation policy を `.regular` に昇格させている。Dock に出ない場合は一度ウィンドウをクリック。
- **Python 3.14 で依存が入らない**: 3.12 を使う（`run.sh` は `python3.12` を呼ぶ）。
