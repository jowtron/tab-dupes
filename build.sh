#!/bin/zsh
# Builds Tab Dupes.app into ./build and, with --install, copies it to /Applications.
set -euo pipefail
cd "${0:A:h}"

APP="build/Tab Dupes.app"
IDENTITY="${CODESIGN_IDENTITY:-Apple Development}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macos14.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/TabDupes"

cp Info.plist "$APP/Contents/Info.plist"
# App icon: drawn by icon/make-icon.swift, then cut into the sizes an .icns needs.
if [[ ! -f icon/AppIcon-1024.png || icon/make-icon.swift -nt icon/AppIcon-1024.png ]]; then
  swift icon/make-icon.swift icon/AppIcon-1024.png
fi
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for px in 16 32 128 256 512; do
  sips -z $px $px icon/AppIcon-1024.png --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
  sips -z $((px * 2)) $((px * 2)) icon/AppIcon-1024.png --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# A real (non ad-hoc) signature keeps the Automation permission across rebuilds.
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --options runtime --entitlements TabDupes.entitlements --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/Tab Dupes.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Tab Dupes.app"
fi
