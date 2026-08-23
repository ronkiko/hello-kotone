#!/usr/bin/env python3
"""Static gate for the isolated KTN-RC3-M03 side gait preview."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / "reference_projects/godot_skeleton2d_demo"
MODEL = PROJECT / "player/kotone_bot_m03"
PARTS = ROOT / "godot/assets/rc3/mannequin/parts/side/m03"
MANIFEST_PATH = PARTS / "m03_side_asset_manifest.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    rig = (MODEL / "neutral_rig.tscn").read_text(encoding="utf-8")
    preview = (MODEL / "preview.tscn").read_text(encoding="utf-8")
    preview_script = (MODEL / "preview.gd").read_text(encoding="utf-8")
    player = (MODEL / "player.tscn").read_text(encoding="utf-8")
    player_script = (MODEL / "player.gd").read_text(encoding="utf-8")
    level = (PROJECT / "level.tscn").read_text(encoding="utf-8")
    launcher = (PROJECT / "m03-side-preview.sh").read_text(encoding="utf-8")

    require(manifest["technical_model"] == "KTN-RC3-M03", "wrong model id")
    require(manifest["view"] == "side_right", "M03 source direction changed")
    require(manifest["normalized_alpha_bounds"] == [546, 54, 708, 1165], "side registration changed")
    require(len(re.findall(r'type="Bone2D"', rig)) == 8, "expected eight M03 bones")
    require(len(re.findall(r'name="Art_[^"]+" type="Sprite2D"', rig)) == 8, "expected eight M03 art nodes")
    require('name="Art_arm_near"' in rig, "separate complete near arm missing")
    require('name="Art_far_thigh"' in rig and 'name="Art_near_thigh"' in rig, "duplicated leg layers missing")
    require('instance=ExtResource("2_rig")' in preview, "preview does not instance M03 rig")
    require('func _sample_leg' in preview_script, "animated preview gait sampler missing")
    require('Side profile: contact -> stance -> toe-off -> bent-knee swing -> contact.' in player_script, "playable side gait contract missing")
    require('visual_pivot.scale.x = 1.0 if direction > 0.0 else -1.0' in player_script, "direction mirror policy missing")
    require('zoom = Vector2(6, 6)' in player, "world camera zoom changed")
    require('path="res://player/kotone_bot_m01/player.tscn" id="4"' in level, "isolated gate must not replace active M01")
    require('godot --headless --path "$SCRIPT_DIR" --import' in launcher, "fresh-clone texture import pass missing")

    for runtime_asset in ("body_head_pelvis.png", "arm_near.png", "thigh.png", "calf.png", "foot.png"):
        require(f'"$ASSET_DIR/{runtime_asset}"' in launcher, f"launcher guard missing: {runtime_asset}")

    normalized = Image.open(PARTS / "kotone_side_right_normalized.png").convert("RGBA")
    require(normalized.size == (1254, 1254), "normalized side canvas changed")
    require(normalized.getchannel("A").getbbox() == (546, 54, 708, 1165), "normalized side alpha bounds changed")

    for part in manifest["parts"]:
        built = PARTS / part["file"]
        copied = MODEL / "assets" / part["file"]
        require(built.is_file(), f"missing built M03 part: {part['name']}")
        require(copied.is_file(), f"missing copied M03 part: {part['name']}")
        require(sha256(built) == part["sha256"], f"built hash mismatch: {part['name']}")
        require(sha256(copied) == part["sha256"], f"runtime hash mismatch: {part['name']}")
        require(Image.open(built).convert("RGBA").getchannel("A").getbbox() is not None, f"empty alpha: {part['name']}")

    require((PROJECT / "player/player.tscn").is_file(), "gBot reference removed")
    require((PROJECT / "player/kotone_bot_m01/player.tscn").is_file(), "M01 rollback removed")
    require((PROJECT / "player/kotone_bot_m02/player.tscn").is_file(), "M02 comparison removed")
    print("KTN-RC3-M03 ISOLATED SIDE GAIT STATIC VALIDATION PASSED")


if __name__ == "__main__":
    main()
