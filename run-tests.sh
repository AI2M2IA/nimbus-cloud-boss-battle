#!/usr/bin/env bash
# Run the headless unit/integration test suite for AWS Boss Battle.
# Usage: ./run-tests.sh        (exits 0 on success, 1 on failure — CI-friendly)
set -euo pipefail

cd "$(dirname "$0")"
scripts/dev/static_audit.py
mkdir -p user-data/home
mkdir -p "$PWD/user-data/home/Library/Application Support"
export HOME="$PWD/user-data/home"
exec ./godot.sh --headless --log-file "$PWD/user-data/godot.log" --path . -s tests/run_tests.gd
