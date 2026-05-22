#!/usr/bin/env bash
set -euo pipefail

# Build a release binary with SwiftPM, then wrap it in a .app bundle.
# Usage:
#   ./build.sh            # builds .build/DigestAnnouncer.app
#   ./build.sh --install  # also copies it to /Applications and opens it

cd "$(dirname "$0")"

APP_NAME="DigestAnnouncer"
BUNDLE_NAME="Digest Announcer.app"
BUILD_DIR=".build"
APP_PATH="$BUILD_DIR/$BUNDLE_NAME"

echo "→ Building release binary…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "Build failed: $BIN_PATH not found" >&2
    exit 1
fi

echo "→ Assembling app bundle at $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp Resources/MenuBarIcon.* "$APP_PATH/Contents/Resources/" 2>/dev/null || true

if [[ -f Resources/AppIcon.png ]]; then
    echo "→ Generating AppIcon.icns"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
                "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
                "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
        size="${spec%%:*}"; name="${spec##*:}"
        sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/$name.png" >/dev/null
    done
    iconutil --convert icns "$ICONSET" --output "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so macOS keychain / network entitlements behave on first launch.
codesign --force --sign - "$APP_PATH" >/dev/null 2>&1 || true

echo "✓ Built: $APP_PATH"

if [[ "${1:-}" == "--install" ]]; then
    DEST="/Applications/$BUNDLE_NAME"
    echo "→ Installing to $DEST"
    rm -rf "$DEST"
    cp -R "$APP_PATH" "$DEST"
    open "$DEST"
    echo "✓ Installed. Add it to System Settings → General → Login Items to run on startup."
fi
