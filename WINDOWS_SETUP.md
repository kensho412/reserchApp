# 帰宅後にやること — Windows デスクトップを LLM サーバにする

外出先の Mac から、自宅 Windows の Ollama を Tailscale 経由で叩けるようにする手順。
所要 30〜40分（モデルのダウンロード時間を除く）。上から順にやれば完了する。

---

## 0. 事前メモ
- **ポート開放（ルーター設定）は一切しない。** 通信は Tailscale だけ。
- Ollama と FastAPI は同じ Windows 上で動かす → 両者の通信は `127.0.0.1` のままでよい。
- Mac から見えるのは FastAPI（8000番）だけ。Ollama（11434番）は外に出さない。

---

## 1. Tailscale を入れる（両方のマシン）
1. Windows: https://tailscale.com/download/windows からインストール → 同じアカウントでログイン。
2. Mac（出先で今のうちにやっておける → 下の「Mac側の準備」参照）も同じアカウントでログイン。
3. Windows で IP を確認：PowerShell で
   ```powershell
   tailscale ip -4
   ```
   → `100.x.x.x` が出る。**この IP を後で Mac アプリに入れる。** メモしておく。

## 2. Python 3.12 を入れる
- https://www.python.org/downloads/release/python-3127/ から Windows installer。
- インストール時に **「Add python.exe to PATH」にチェック**。
- 確認：
  ```powershell
  py -3.12 --version
  ```
  （3.14 ではなく 3.12。PyMuPDF / Chroma の wheel の都合）

## 3. Ollama を入れてモデルを取得
1. https://ollama.com/download/windows からインストール（自動で常駐サービスになる）。
2. PowerShell で：
   ```powershell
   ollama pull qwen2.5:7b
   ollama pull nomic-embed-text
   ```
3. 動作確認：
   ```powershell
   ollama run qwen2.5:7b "こんにちは"
   ```
   返事が返ればOK。

## 4. このプロジェクトを Windows に置く
- `reserchApp` フォルダごと Windows にコピー（USB / クラウド / git どれでも）。
- `backend/.venv` と `macapp/.build` はコピー不要（環境依存なので作り直す）。`.gitignore` 済み。

## 5. バックエンドを起動
PowerShell で `backend` フォルダに移動して：
```powershell
cd path\to\reserchApp\backend
./run.ps1 -BindAll
```
- 初回は venv 作成＋依存インストールで数分かかる。
- `uvicorn を 0.0.0.0:8000 で起動します` と出れば成功。
- ⚠️ もし「スクリプトの実行が無効」と出たら：
  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
  ```
  を一度実行してから再度 `./run.ps1 -BindAll`。

## 6. Windows ファイアウォールで 8000番を許可
Mac から届くようにする。PowerShell を**管理者として**開いて：
```powershell
New-NetFirewallRule -DisplayName "ResearchAtlas 8000" -Direction Inbound `
  -Protocol TCP -LocalPort 8000 -Action Allow -Profile Private
```
（`-Profile Private` 推奨。Tailscale は通常 Private ネットワーク扱い。届かない場合は一時的に `Any` で試す。）

## 7. Mac アプリから接続
1. Mac で `cd macapp && swift run` でアプリ起動。
2. 右上の歯車 → **Server URL** に
   ```
   http://100.x.x.x:8000
   ```
   （手順1で控えた Windows の Tailscale IP）→「適用」。
3. ホーム画面にタグが並べば接続成功。ページを作って URL を貼ると、Windows の Ollama が要約・タグ・翻訳を返す。

---

## 動作確認チェックリスト
- [ ] `tailscale status` で Mac と Windows が両方 online
- [ ] Windows で `http://127.0.0.1:8000/health` が `{"status":"ok","ollama":true}` を返す
- [ ] Mac のブラウザで `http://100.x.x.x:8000/health` が開ける（← ここが通れば配線は完成）
- [ ] Mac アプリでページ作成 → URL 貼付 → 数秒後に要約が出る

## つまずいたら
- **`ollama:false` が返る** → Ollama サービスが起動していない / モデル未取得。`ollama list` で確認。
- **Mac から `/health` が開けない** → ①Tailscale 両方ログイン済みか ②ファイアウォール許可（手順6）③`run.ps1` を `-BindAll` で起動したか（`127.0.0.1` 起動だと外から見えない）。
- **要約が遅い／途中で止まる** → 7Bモデルは初回ロードが重い。Mac アプリ側はLLM呼び出しを最大10〜15分待つよう設定済みなので、そのまま待てばよい。GPUが載っていれば大幅に速くなる。
- **常時起動にしたい** → Windows のタスクスケジューラで「ログオン時に `run.ps1 -BindAll` を実行」を登録。Ollama は既にサービス常駐。

---

## 今 Mac 側でやっておける準備（出先でOK）
1. **Tailscale を Mac に入れてログイン**（App Store または https://tailscale.com/download/mac）。これだけ先にやっておくと帰宅後は Windows を足すだけ。
2. **Mac アプリがビルドできることを確認**：`cd macapp && swift build`（このリポジトリで確認済み）。
3. Server URL は帰宅後に Windows の IP が分かってから入れる。それまではローカル（`127.0.0.1:8000`）のままで、Mac 上で `backend/run.sh` を動かして単体で試せる。
