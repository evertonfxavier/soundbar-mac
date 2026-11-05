#!/usr/bin/env bash
# Builds build/SoundBar.app from Sources/SoundBar with swiftc. It needs only the Command Line Tools: no Xcode, and no
# Swift Package Manager (the manifest API of some Command Line Tools releases does not even link).
#
#   scripts/build-app.sh [--run]      --run quits a running SoundBar and opens the new build
#
# Environment, all optional:
#   SOUNDBAR_VERSION   version shown to the user         (default: the VERSION file)
#   SOUNDBAR_BUILD     build number                      (default: 1)
#   ARCHS              "arm64", "x86_64", or both separated by a space for a universal app (default: this machine's)
#   SIGN_IDENTITY      codesign identity                 (default: "-", an ad-hoc signature that runs on this Mac only)
#   OUT_DIR            where the app is put              (default: build)
#   SWIFTFLAGS         extra flags for swiftc, e.g. -warnings-as-errors
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=SoundBar
VERSION="${SOUNDBAR_VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD="${SOUNDBAR_BUILD:-1}"
ARCHS="${ARCHS:-$(uname -m)}"
IDENTITY="${SIGN_IDENTITY:--}"
OUT_DIR="${OUT_DIR:-build}"
APP="$OUT_DIR/$NAME.app"
MIN_MACOS=14.2 # the first macOS with Core Audio process taps; keep in Info.plist (LSMinimumSystemVersion)

sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find Sources/SoundBar -name '*.swift' | sort)

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# One binary per architecture, joined with lipo when there is more than one.
slices=()
for arch in $ARCHS; do
  echo "Compiling $NAME ($arch)…"
  # shellcheck disable=SC2086 # SWIFTFLAGS is a list of flags on purpose
  swiftc -O -parse-as-library \
    -target "$arch-apple-macos$MIN_MACOS" \
    -swift-version 5 \
    -framework CoreAudio -framework AppKit -framework ServiceManagement \
    ${SWIFTFLAGS:-} \
    "${sources[@]}" \
    -o "$work/$NAME-$arch"
  slices+=("$work/$NAME-$arch")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ ${#slices[@]} -gt 1 ]]; then
  lipo -create "${slices[@]}" -output "$APP/Contents/MacOS/$NAME"
else
  cp "${slices[0]}" "$APP/Contents/MacOS/$NAME"
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The texts of the permission dialogs, one folder per language (Resources/<language>.lproj)
cp -R Resources/*.lproj "$APP/Contents/Resources/"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD" "$APP/Contents/Info.plist"

# Hardened runtime on every build (a notarized app needs it, and it is better to meet it early).
sign=(--force --options runtime --entitlements Resources/SoundBar.entitlements --sign "$IDENTITY")
if [[ "$IDENTITY" == "-" ]]; then sign+=(--timestamp=none); else sign+=(--timestamp); fi
codesign "${sign[@]}" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP  (version $VERSION, build $BUILD, $ARCHS, signed with ${IDENTITY/#-/ad hoc})"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x "$NAME" 2>/dev/null || true
  sleep 0.5
  open "$APP"
fi
