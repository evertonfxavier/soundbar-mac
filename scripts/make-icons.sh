#!/usr/bin/env bash
# Renders the icons from the SVG masters in assets/:
#   assets/icon-app.svg             -> Resources/AppIcon.icns                (macOS app icon, via iconutil)
#   assets/icon-extension*.svg      -> ChromeExtension/public/icons/icon-{16,32,48,128}.png
#
# The results are committed, so a build never needs these tools: run this only after editing an SVG.
# Needs: rsvg-convert (brew install librsvg) and iconutil (macOS).
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in rsvg-convert iconutil; do
  command -v "$tool" >/dev/null || { echo "error: '$tool' not found (brew install librsvg)" >&2; exit 1; }
done

render() { # render <svg> <size> <png>
  rsvg-convert --width "$2" --height "$2" "$1" --output "$3"
}

# ---------- Chrome extension ----------
ext_dir="ChromeExtension/public/icons"
mkdir -p "$ext_dir"
# 16 and 32 use the simplified artwork (it has to read in a toolbar); 48 and 128 use the full one.
render assets/icon-extension-small.svg 16 "$ext_dir/icon-16.png"
render assets/icon-extension-small.svg 32 "$ext_dir/icon-32.png"
render assets/icon-extension.svg 48 "$ext_dir/icon-48.png"
render assets/icon-extension.svg 128 "$ext_dir/icon-128.png"

# ---------- macOS app ----------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
for base in 16 32 128 256 512; do
  render assets/icon-app.svg "$base" "$iconset/icon_${base}x${base}.png"
  render assets/icon-app.svg "$((base * 2))" "$iconset/icon_${base}x${base}@2x.png"
done
mkdir -p Resources
iconutil --convert icns "$iconset" --output Resources/AppIcon.icns

echo "Icons written: Resources/AppIcon.icns and $ext_dir/"
