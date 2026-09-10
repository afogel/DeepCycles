#!/bin/bash
# Builds DeepCycles.app. Requires macOS 14+ and Xcode Command Line Tools:
#   xcode-select --install
# Usage:  ./build.sh            -> build/DeepCycles.app
#         ./build.sh --install  -> also copies to /Applications
# Tests:  swift run DeepCyclesCoreTests
set -euo pipefail
cd "$(dirname "$0")"

echo "Compiling (release)..."
swift build -c release 2>&1 | grep -v "^\[" || true
BIN=".build/release/DeepCycles"
[[ -x "$BIN" ]] || { echo "Build failed — see errors above."; exit 1; }

APP="build/DeepCycles.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DeepCycles"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon from typography (rendered here so it uses the real system serif)
if command -v iconutil >/dev/null; then
  ICONSET="build/DeepCycles.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  swift Resources/make_icon.swift build/icon_1024.png >/dev/null 2>&1 && {
    for s in 16 32 128 256 512; do
      sips -z $s $s build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
      sips -z $((s*2)) $((s*2)) build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" && echo "Icon rendered."
  } || echo "Icon skipped (script failed); the app still works."
fi
echo "APPL????" > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/DeepCycles.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/DeepCycles.app — open it from Launchpad or Spotlight."
fi
