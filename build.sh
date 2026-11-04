#!/bin/bash
# Builds build/SoundBar.app. Usage: ./build.sh [--run]
# Kept for the habit: the work is in scripts/build-app.sh, where the options (version, architectures, signing) are.
exec "$(dirname "$0")/scripts/build-app.sh" "$@"
