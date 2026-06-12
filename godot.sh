#!/usr/bin/env bash
# Project-local Godot shortcut. With no arguments it runs this project;
# otherwise it passes all arguments through to Godot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="${GODOT:-}"

if [ -z "$GODOT" ]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT="$(command -v godot)"
  elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
  elif [ -x "/Applications/Godot.app/Contents/MacOS/godot" ]; then
    GODOT="/Applications/Godot.app/Contents/MacOS/godot"
  else
    echo "Godot 4 not found. Install it, add it to PATH, or run: GODOT=/path/to/godot ./godot.sh" >&2
    exit 1
  fi
fi

if [ "$#" -eq 0 ]; then
  exec "$GODOT" --path "$ROOT"
fi

exec "$GODOT" "$@"
