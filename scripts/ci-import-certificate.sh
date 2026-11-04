#!/usr/bin/env bash
# CI only. Puts a Developer ID certificate in a temporary keychain, so codesign can use it, and prints the name of the
# signing identity it holds. The keychain is thrown away with the runner.
#
#   echo "SIGN_IDENTITY=$(scripts/ci-import-certificate.sh)" >> "$GITHUB_ENV"
#
# Needs, in the environment: MACOS_CERTIFICATE (a .p12 file, base64 encoded) and MACOS_CERTIFICATE_PASSWORD.
set -euo pipefail

: "${MACOS_CERTIFICATE:?MACOS_CERTIFICATE is not set}"
: "${MACOS_CERTIFICATE_PASSWORD:?MACOS_CERTIFICATE_PASSWORD is not set}"
: "${RUNNER_TEMP:?RUNNER_TEMP is not set (this script is for GitHub Actions)}"

keychain="$RUNNER_TEMP/soundbar-signing.keychain-db"
keychain_password="$(uuidgen)"
certificate="$RUNNER_TEMP/soundbar-certificate.p12"

# Everything that is not the identity goes to stderr: the caller captures stdout.
{
  security create-keychain -p "$keychain_password" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$keychain_password" "$keychain"

  printf '%s' "$MACOS_CERTIFICATE" | base64 --decode >"$certificate"
  security import "$certificate" -k "$keychain" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
  rm -f "$certificate"

  # Lets codesign use the key without a password prompt that nobody could answer.
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain"

  # The new keychain goes first in the search list, the others stay.
  # shellcheck disable=SC2046 # the list of keychains is meant to be split into words
  security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
} >&2

identity="$(security find-identity -v -p codesigning "$keychain" | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
if [[ -z "$identity" ]]; then
  echo "error: no \"Developer ID Application\" identity in the certificate" >&2
  exit 1
fi
echo "$identity"
