#!/bin/bash
# Build the macOS app from kBox.xcodeproj.
#   scripts/build-app.sh            release build → build/kBox.app
#   scripts/build-app.sh --open     …and launch it
#   scripts/build-app.sh --debug    debug build (keeps the KBOX_* debug hooks)
# For iPad, run the kBox scheme from Xcode with an iPad / simulator destination.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=Release
OPEN=0
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG=Debug ;;
    --open) OPEN=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# App icon (regenerated only when the drawing script changes)
ICON_DIR=App/Assets.xcassets/AppIcon.appiconset
if [[ ! -f "$ICON_DIR/Contents.json" || scripts/make-icon.swift -nt "$ICON_DIR/Contents.json" ]]; then
  swift scripts/make-icon.swift "$ICON_DIR"
fi

xcodebuild -project kBox.xcodeproj -scheme kBox -configuration "$CONFIG" \
  -destination 'platform=macOS' -derivedDataPath build/dd build | tail -1

BUILT="build/dd/Build/Products/$CONFIG/kBox.app"
APP="build/kBox.app"
rm -rf "$APP"
cp -R "$BUILT" "$APP"
echo "Built $APP"

if [[ $OPEN == 1 ]]; then
  open "$APP"
fi
