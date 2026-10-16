#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
godot_bin="$(command -v "${GODOT_BIN:-godot}")"
python3 "$here/run_smoke.py" "$godot_bin"
