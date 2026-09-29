#!/bin/bash
# Build Boogie.app and (with --install) copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Boogie.app"
for person in sophia manuel; do
    test -f "assets/characters/$person/animation.json" || { echo "Missing character assets: $person" >&2; exit 1; }
done
export MACOSX_DEPLOYMENT_TARGET=13.0
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -import-objc-header Sources/Private.h -framework IOKit Sources/*.swift -o "$APP/Contents/MacOS/Boogie"
cp Info.plist "$APP/Contents/Info.plist"
cp -R assets/characters "$APP/Contents/Resources/Characters"
cp assets/CHARACTERS.md "$APP/Contents/Resources/Character Credits.md"

# Render the studio wordmark icon; the same tool also makes pixel-cast previews.
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
