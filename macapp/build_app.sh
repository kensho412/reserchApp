#!/usr/bin/env bash
# Build ResearchAtlas.app - a double-clickable macOS app bundle.
#
#   ./build_app.sh            # builds ./ResearchAtlas.app
#   ./build_app.sh --install  # also copies it into /Applications
#
# To update later: `git pull` then run this again. No Apple Developer account
# or code signing needed for personal use (Gatekeeper note below).
set -euo pipefail
cd "$(dirname "$0")"

APP="ResearchAtlas.app"
BIN="ResearchAtlas"
VERSION="0.1.0"

echo "==> Building release binary..."
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$BIN"

echo "==> Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN"

ICON_LINE=""
if [[ -f AppIcon.icns ]]; then
    cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    ICON_LINE="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ResearchAtlas</string>
    <key>CFBundleDisplayName</key><string>Research Atlas</string>
    <key>CFBundleIdentifier</key><string>com.researchatlas.app</string>
    <key>CFBundleExecutable</key><string>$BIN</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    $ICON_LINE
    <!-- Backend is plain HTTP over Tailscale; allow cleartext loads. -->
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

# Ad-hoc sign so the app runs without "is damaged" errors on Apple Silicon.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "   (codesign skipped - app still runs; see Gatekeeper note)"

echo "==> Built $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications..."
    rm -rf "/Applications/$APP"
    cp -R "$APP" "/Applications/$APP"
    echo "   Installed. Launch from Spotlight or /Applications."
fi

cat <<'NOTE'

Done. Open it with:  open ./ResearchAtlas.app
First launch: macOS may say "unidentified developer". Right-click the app ->
Open -> Open (only needed once), or run:  xattr -dr com.apple.quarantine ResearchAtlas.app

Reminder: this is the Mac client only. The FastAPI + Ollama backend still runs
on your Windows desktop; set the server URL (gear icon) to its Tailscale IP.
NOTE
