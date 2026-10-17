#!/bin/bash
# Builds a universal MyAltTab.app, signs it, installs it to ~/Applications and zips it for other Macs.
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary (Apple Silicon + Intel). Each arch gets its own scratch dir since they share an output path.
BINARIES=()
for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx14.0" --scratch-path ".build/$ARCH"
    BINARIES+=("$(swift build -c release --triple "$ARCH-apple-macosx14.0" --scratch-path ".build/$ARCH" --show-bin-path)/MyAltTab")
done

APP=build/MyAltTab.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/MyAltTab"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sign with a stable self-signed identity so macOS keeps permissions across rebuilds.
# Hardened runtime blocks DYLD_INSERT_LIBRARIES and similar injection into a process holding
# Accessibility and Screen Recording access. The signing keychain is locked again right after.
./scripts/setup_signing.sh
trap 'security lock-keychain "$HOME/Library/Keychains/myalttab-signing.keychain-db"' EXIT
codesign --force --options runtime --sign "MyAltTab Self-Signed" "$APP"
security lock-keychain "$HOME/Library/Keychains/myalttab-signing.keychain-db"
trap - EXIT

DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x MyAltTab 2>/dev/null || true
rm -rf "$DEST/MyAltTab.app"
cp -R "$APP" "$DEST/"

# Zip for copying to another Mac (ditto keeps the signature and bundle metadata intact).
rm -f build/MyAltTab.zip
ditto -c -k --keepParent "$APP" build/MyAltTab.zip

echo "Installed $DEST/MyAltTab.app"
echo "Zip for other Macs: $(pwd)/build/MyAltTab.zip"
echo "Run: open \"$DEST/MyAltTab.app\""
