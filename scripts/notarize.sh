#!/usr/bin/env bash
# Sends the app (zipped for the upload) or the disk image to Apple's notary service, waits for the verdict and staples
# the ticket to it, so Gatekeeper opens it without asking and without a network.
#
#   scripts/notarize.sh build/SoundBar.app
#   scripts/notarize.sh build/SoundBar-v0.1.0.dmg
#
# Needs a Developer ID signature on the thing it sends (scripts/build-app.sh with SIGN_IDENTITY set) and, in the
# environment: NOTARY_APPLE_ID, NOTARY_TEAM_ID and NOTARY_PASSWORD (an app-specific password, not the Apple ID's own).
set -euo pipefail

target="${1:?usage: scripts/notarize.sh <SoundBar.app | SoundBar.dmg>}"
: "${NOTARY_APPLE_ID:?NOTARY_APPLE_ID is not set}"
: "${NOTARY_TEAM_ID:?NOTARY_TEAM_ID is not set}"
: "${NOTARY_PASSWORD:?NOTARY_PASSWORD is not set}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The service takes a zip, a disk image or an installer, not a bare app.
upload="$target"
if [[ -d "$target" ]]; then
  upload="$work/$(basename "$target").zip"
  ditto -c -k --keepParent "$target" "$upload"
fi

credentials=(--apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD")

echo "Notarizing $target (this takes a few minutes)…"
result="$(xcrun notarytool submit "$upload" "${credentials[@]}" --wait --timeout 30m --output-format json)"
status="$(printf '%s' "$result" | plutil -extract status raw -o - -)"
id="$(printf '%s' "$result" | plutil -extract id raw -o - -)"

if [[ "$status" != "Accepted" ]]; then
  echo "error: the notary service said \"$status\" for $id. Its log:" >&2
  xcrun notarytool log "$id" "${credentials[@]}" >&2 || true
  exit 1
fi

xcrun stapler staple "$target"
xcrun stapler validate "$target"
echo "Notarized and stapled: $target"
