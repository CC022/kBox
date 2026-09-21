#!/bin/bash
# Build kBox.app from the Swift package.
#   scripts/build-app.sh            release build → build/kBox.app
#   scripts/build-app.sh --open     …and launch it
#   scripts/build-app.sh --debug    debug build (keeps --demo/--snapshot launch flags) → build/debug/kBox.app
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
OUT=build
OPEN=0
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG=debug; OUT=build/debug ;;
    --open) OPEN=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/kBox"

# App icon (regenerated only when the drawing script changes)
ICNS=build/AppIcon.icns
if [[ ! -f "$ICNS" || scripts/make-icon.swift -nt "$ICNS" ]]; then
  rm -rf build/AppIcon.iconset
  mkdir -p build
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o "$ICNS"
fi

APP="$OUT/kBox.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/kBox"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.kbox</string>
  <key>CFBundleName</key><string>kBox</string>
  <key>CFBundleDisplayName</key><string>kBox</string>
  <key>CFBundleExecutable</key><string>kBox</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>
  <key>LSApplicationCategoryType</key><string>public.app-category.finance</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ $OPEN == 1 ]]; then
  open "$APP"
fi
