#!/usr/bin/env bash
# Start the Research Atlas backend.
#
# Dev (same machine as the Mac app):
#   ./run.sh
# Home desktop server (reachable from the Mac over Tailscale only):
#   HOST=0.0.0.0 ./run.sh
#
# NEVER port-forward this. Bind to 0.0.0.0 only behind Tailscale.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
  python3.12 -m venv .venv
  ./.venv/bin/pip install -U pip
  ./.venv/bin/pip install -r requirements.txt
fi

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"
exec ./.venv/bin/uvicorn app.main:app --host "$HOST" --port "$PORT" --reload
