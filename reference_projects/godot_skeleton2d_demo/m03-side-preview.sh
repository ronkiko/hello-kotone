#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec godot --path "$SCRIPT_DIR" \
  res://player/kotone_bot_m03/preview.tscn "$@"
