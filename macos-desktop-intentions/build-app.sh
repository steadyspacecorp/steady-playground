#!/bin/bash
# Builds "Steady Intentions.app" from the Swift package — no Xcode project needed.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Steady Intentions"
BUNDLE_ID="space.steady.intentions"
BIN_NAME="SteadyIntentions"
CONFIG="${1:-release}"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"
APP_DIR="build/$APP_NAME.app"

echo "▸ Assembling ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$BIN_NAME"

# Generate AppIcon.icns from Resources/AppIcon.png at every size macOS expects.
# Pure /usr/bin/sips + /usr/bin/iconutil, no external tools needed.
ICON_NAME=""
if [[ -f "Resources/AppIcon.png" ]]; then
    echo "▸ Building AppIcon.icns from Resources/AppIcon.png…"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for spec in \
        "16:icon_16x16.png" \
        "32:icon_16x16@2x.png" \
        "32:icon_32x32.png" \
        "64:icon_32x32@2x.png" \
        "128:icon_128x128.png" \
        "256:icon_128x128@2x.png" \
        "256:icon_256x256.png" \
        "512:icon_256x256@2x.png" \
        "512:icon_512x512.png" \
        "1024:icon_512x512@2x.png"
    do
        size="${spec%%:*}"
        name="${spec##*:}"
        sips -z "$size" "$size" "Resources/AppIcon.png" --out "$ICONSET/$name" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    ICON_NAME="AppIcon"
fi

# Menu bar icon — copy SVG into the bundle; NSImage loads it as a template at
# runtime, AppKit tints it per dark/light + highlight state.
if [[ -f "Resources/MenuBarIcon.svg" ]]; then
    cp "Resources/MenuBarIcon.svg" "$APP_DIR/Contents/Resources/MenuBarIcon.svg"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$BIN_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <!-- Menu-bar agent: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Steady Intentions</string>${ICON_NAME:+
    <key>CFBundleIconFile</key>
    <string>$ICON_NAME</string>
    <key>CFBundleIconName</key>
    <string>$ICON_NAME</string>}
</dict>
</plist>
PLIST

# Ad-hoc sign so Keychain access and Gatekeeper behave on the local machine.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✓ Built $APP_DIR"
echo "  Run it with:  open \"$APP_DIR\""
