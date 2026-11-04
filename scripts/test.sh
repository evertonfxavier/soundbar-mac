#!/usr/bin/env bash
# Compiles Sources/SoundBar/Core (everything but the SwiftUI app) together with Tests/ and runs the tests, which are
# written with Swift Testing. Like scripts/build-app.sh it uses swiftc alone, so it works with the Command Line Tools
# or with Xcode, and it is what the pipeline runs.
#
#   scripts/test.sh [swift-testing options]      e.g. --filter AppSetting
#
# Compiling only Core is also a check of the architecture: Core cannot reach the views, or this does not build.
#
# Environment, all optional:
#   SWIFTFLAGS   extra flags for swiftc, e.g. -warnings-as-errors
set -euo pipefail
cd "$(dirname "$0")/.."

MIN_MACOS=14.2

# Where this machine keeps Swift Testing: the Command Line Tools and Xcode lay it out differently.
developer_dir="$(xcode-select -p)"
platform_dir="$(xcrun --show-sdk-platform-path 2>/dev/null || true)"
toolchain_bin="$(dirname "$(xcrun --find swiftc)")"

first_dir_with() { # first_dir_with <file> <dir>…: the first directory that holds <file>
  local file="$1"
  shift
  local dir
  for dir in "$@"; do
    if [[ -n "$dir" && -e "$dir/$file" ]]; then
      echo "$dir"
      return 0
    fi
  done
  return 1
}

frameworks="$(first_dir_with Testing.framework \
  "$developer_dir/Library/Developer/Frameworks" "$platform_dir/Developer/Library/Frameworks")" || {
  echo "error: Testing.framework not found. Install the Command Line Tools (xcode-select --install) or Xcode 16+." >&2
  exit 1
}
# Newer toolchains keep a helper library next to it; older ones do not have it.
interop="$(first_dir_with lib_TestingInterop.dylib \
  "$developer_dir/Library/Developer/usr/lib" "$platform_dir/Developer/usr/lib" || true)"
plugins="$toolchain_bin/../lib/swift/host/plugins/testing"

rpaths=(-Xlinker -rpath -Xlinker "$frameworks")
if [[ -n "$interop" ]]; then rpaths+=(-Xlinker -rpath -Xlinker "$interop"); fi

core=()
while IFS= read -r file; do core+=("$file"); done < <(find Sources/SoundBar/Core -name '*.swift' | sort)
tests=()
while IFS= read -r file; do tests+=("$file"); done < <(find Tests -name '*.swift' | sort)

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Compiling ${#core[@]} source files and ${#tests[@]} test files…"
# shellcheck disable=SC2086 # SWIFTFLAGS is a list of flags on purpose
swiftc -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macos$MIN_MACOS" \
  -F "$frameworks" -plugin-path "$plugins" -framework Testing "${rpaths[@]}" \
  -framework CoreAudio -framework AppKit -framework ServiceManagement \
  ${SWIFTFLAGS:-} \
  "${core[@]}" "${tests[@]}" \
  -o "$work/SoundBarTests"

"$work/SoundBarTests" "$@"
