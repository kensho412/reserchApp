#!/usr/bin/env bash
# Double-click this file to update Research Atlas to the latest version:
# pulls the newest code, rebuilds the .app, and installs it to /Applications.
#
# (Right-click -> Open the first time if macOS blocks it.)
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Updating Research Atlas…"
echo "==> Pulling latest code…"
git pull --ff-only

echo "==> Rebuilding the app…"
cd macapp
./build_app.sh --install

echo ""
echo "✅ Updated. Research Atlas is in /Applications."
echo "   (You can close this window.)"
