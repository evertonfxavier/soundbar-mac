#!/usr/bin/env bash
# Packs the app into build/SoundBar-v<version>.dmg: a disk image with the app and a shortcut to /Applications, so
# installing is dragging one onto the other.
#
#   scripts/make-dmg.sh [path/to/SoundBar.app]      (default: build/SoundBar.app, from scripts/build-app.sh)
#
# Environment, all optional:
#   SIGN_IDENTITY   codesign identity for the image (default: "-", which leaves the image unsigned)
#   OUT_DIR         where the image is put           (default: next to the app)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-build/SoundBar.app}"
[[ -d "$APP" ]] || {
  echo "error: $APP not found (run scripts/build-app.sh first)" >&2
  exit 1
}

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
OUT_DIR="${OUT_DIR:-$(dirname "$APP")}"
IDENTITY="${SIGN_IDENTITY:--}"
DMG="$OUT_DIR/SoundBar-v$VERSION.dmg"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

# `ditto` keeps the code signature and the extended attributes that a plain `cp -R` can lose.
ditto "$APP" "$stage/$(basename "$APP")"
ln -s /Applications "$stage/Applications"

mkdir -p "$OUT_DIR"
rm -f "$DMG"
hdiutil create -volname "SoundBar" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov -quiet "$DMG"

if [[ "$IDENTITY" != "-" ]]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
fi

echo "Built $DMG"
