#!/usr/bin/env bash
# Launch AWS Boss Battle (equivalent to pressing F5 in the editor).
# Usage: ./run-game.sh
set -euo pipefail

cd "$(dirname "$0")"
exec ./godot.sh
