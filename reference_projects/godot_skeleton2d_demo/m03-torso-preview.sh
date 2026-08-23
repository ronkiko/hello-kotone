#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TORSO_ASSET="$SCRIPT_DIR/player/kotone_bot_m03/assets/torso.png"

if [[ ! -s "$TORSO_ASSET" ]]; then
  echo "M03 torso preview asset is missing or empty: $TORSO_ASSET" >&2
  exit 1
fi

# A freshly pulled PNG has no Godot import cache yet. Import first so the
# Texture2D resource resolves before the isolated preview scene is parsed.
godot --headless --path "$SCRIPT_DIR" --import

exec godot --path "$SCRIPT_DIR" \
  res://player/kotone_bot_m03/torso_preview.tscn "$@"

