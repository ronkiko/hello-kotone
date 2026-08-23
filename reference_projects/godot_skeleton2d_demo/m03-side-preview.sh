#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ASSET_DIR="$SCRIPT_DIR/player/kotone_bot_m03/assets"
REQUIRED_ASSETS=(
  "$ASSET_DIR/body_head_pelvis.png"
  "$ASSET_DIR/upper_arm.png"
  "$ASSET_DIR/forearm.png"
  "$ASSET_DIR/hand.png"
  "$ASSET_DIR/thigh.png"
  "$ASSET_DIR/calf.png"
  "$ASSET_DIR/foot.png"
)

for asset_path in "${REQUIRED_ASSETS[@]}"; do
  if [[ ! -s "$asset_path" ]]; then
    echo "M03 preview asset is missing or empty: $asset_path" >&2
    exit 1
  fi
done

# A freshly pulled PNG has no Godot import cache yet. Import the project first
# so every ext_resource resolves as Texture2D when the preview scene is parsed.
godot --headless --path "$SCRIPT_DIR" --import

exec godot --path "$SCRIPT_DIR" \
  res://player/kotone_bot_m03/preview.tscn "$@"
