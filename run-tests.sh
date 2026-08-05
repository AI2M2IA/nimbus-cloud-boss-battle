#!/usr/bin/env bash
# Run the headless unit/integration test suite for AWS Boss Battle.
# Usage: ./run-tests.sh        (exits 0 on success, 1 on failure — CI-friendly)
set -euo pipefail

cd "$(dirname "$0")"
scripts/dev/static_audit.py
mkdir -p user-data/home
mkdir -p "$PWD/user-data/home/Library/Application Support"
export HOME="$PWD/user-data/home"
LOG="$PWD/user-data/godot.log"

# On a clean clone, .godot/ (the import cache) doesn't exist yet. Most
# resources tolerate that -- Godot imports them on demand the first time
# something asks -- but the project-wide default font (gui/theme/custom_font)
# loads very early, during theme initialization, before that on-demand path
# kicks in, so a never-imported project failed here with a Parse Error
# instead of a clean pass *or* a clean, well-labeled failure. Import first,
# every time, so this script is self-sufficient on a fresh checkout instead
# of silently depending on CI's separate --import step to paper over it.
./godot.sh --headless --path . --import >/dev/null 2>&1 || true

# Godot can log a script compile/parse error (e.g. a bare global class_name
# reference that isn't registered yet) while still returning a non-null
# scene/instance, so the GDScript-level checks in tests/run_tests.gd can pass
# even when something is actually broken. Belt-and-suspenders: grep the run's
# own log for those error classes and fail regardless of Godot's exit code.
set +e
./godot.sh --headless --log-file "$LOG" --path . -s tests/run_tests.gd
status=$?
set -e

if grep -qE "SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script" "$LOG"; then
  echo "" >&2
  echo "run-tests.sh: Godot logged a script compile/parse error during the run:" >&2
  grep -E "SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script" "$LOG" >&2
  exit 1
fi

exit "$status"
