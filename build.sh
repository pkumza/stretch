#!/bin/bash
# Build Stretch and assemble a runnable Stretch.app bundle.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="Stretch.app"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Stretch"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Stretch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Assets/Stretch.icns ]; then
    cp Assets/Stretch.icns "$APP/Contents/Resources/Stretch.icns"
fi

# Ad-hoc sign so macOS is happy launching it locally.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "==> done: $(pwd)/$APP"
echo "    Launch with:  open '$(pwd)/$APP'"
