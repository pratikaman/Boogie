#!/bin/bash
# Build Boogie.app and (with --install) copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Boogie.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/Boogie"
cp Info.plist "$APP/Contents/Info.plist"

# The app icon is rendered from the sprite itself, so the pixel art in
# Sources/Sprite.swift is the single source of truth.
swiftc -O Sources/Sprite.swift tools/main.swift -o build/render
./build/render assets icon >/dev/null

ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size assets/icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) assets/icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force -s - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/Boogie.app
    cp -R "$APP" ~/Applications/
    touch ~/Applications/Boogie.app
    echo "Installed to ~/Applications/Boogie.app"
fi
