#!/bin/bash
# Generate Assets/icon-1024.png and assemble Assets/Stretch.icns from it.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> rendering master PNG"
swift tools/IconGen.swift Assets/icon-1024.png

echo "==> building iconset"
ICONSET="Assets/Stretch.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

gen() { # gen <px> <filename>
    sips -z "$1" "$1" Assets/icon-1024.png --out "$ICONSET/$2" >/dev/null
}
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp Assets/icon-1024.png "$ICONSET/icon_512x512@2x.png"

echo "==> iconutil -> Assets/Stretch.icns"
iconutil -c icns "$ICONSET" -o Assets/Stretch.icns
rm -rf "$ICONSET"
echo "==> done: Assets/Stretch.icns"
