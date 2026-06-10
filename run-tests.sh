#!/usr/bin/env bash
# Run the headless unit/integration test suite for AWS Boss Battle.
# Locates Godot 4 from $GODOT, the PATH, or the standard macOS app path.
# Usage: ./run-tests.sh        (exits 0 on success, 1 on failure — CI-friendly)
set -euo pipefail

GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT="$(command -v godot)"
  elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
  elif [ -x "/Applications/Godot.app/Contents/MacOS/godot" ]; then
    GODOT="/Applications/Godot.app/Contents/MacOS/godot"
  else
    echo "Godot 4 not found. Install it, add it to PATH, or run: GODOT=/path/to/godot ./run-tests.sh" >&2
    exit 1
  fi
fi

cd "$(dirname "$0")"
exec "$GODOT" --headless --path . -s tests/run_tests.gd
