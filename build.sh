#!/bin/bash
# Builds MyAltTab.app, signs it and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MyAltTab"

APP=build/MyAltTab.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MyAltTab"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sign with a stable self-signed identity so macOS keeps permissions across rebuilds.
./scripts/setup_signing.sh
codesign --force --sign "MyAltTab Self-Signed" "$APP"

DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x MyAltTab 2>/dev/null || true
rm -rf "$DEST/MyAltTab.app"
cp -R "$APP" "$DEST/"

echo "Installed $DEST/MyAltTab.app"
echo "Run: open \"$DEST/MyAltTab.app\""
