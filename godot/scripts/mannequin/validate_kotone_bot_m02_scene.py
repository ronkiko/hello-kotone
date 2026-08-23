#!/usr/bin/env python3
"""Static gate for the isolated KTN-RC3-M02 side gait preview."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / "reference_projects/godot_skeleton2d_demo"
MODEL = PROJECT / "player/kotone_bot_m02"
PARTS = ROOT / "godot/assets/rc3/mannequin/parts/side/m02"
MANIFEST_PATH = PARTS / "m02_side_asset_manifest.json"


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
    launcher = (PROJECT / "m02-side-preview.sh").read_text(encoding="utf-8")
    m03 = json.loads((PROJECT / "player/kotone_bot_m03/model_manifest.json").read_text(encoding="utf-8"))

    require(manifest["technical_model"] == "KTN-RC3-M02", "wrong model id")
    require(manifest["view"] == "side_right", "M02 source direction changed")
    require(manifest["source_body"].endswith("kotone_side_right_no_arms_source.png"), "clean no-arm body source missing")
    require(manifest["normalized_alpha_bounds"] == [546, 54, 708, 1165], "side registration changed")
    require(manifest["pivots"]["hip"] == [619, 575], "measured hip pivot changed")
    require(manifest["pivots"]["knee"] == [609, 775], "measured knee pivot changed")
    require(manifest["pivots"]["ankle"] == [593, 1060], "measured ankle pivot changed")
    require(manifest["pivots"]["shoulder"] == [594, 254], "measured shoulder pivot changed")
    require(manifest["pivots"]["elbow"] == [595, 390], "measured elbow pivot changed")
    require(manifest["pivots"]["wrist"] == [597, 521], "measured wrist pivot changed")
    require(len(re.findall(r'type="Bone2D"', rig)) == 13, "expected thirteen M02 bones")
    require(len(re.findall(r'name="Art_[^"]+" type="Sprite2D"', rig)) == 13, "expected thirteen M02 art nodes")
    require('name="Art_far_upper_arm"' in rig and 'name="Art_near_upper_arm"' in rig, "two upper arms missing")
    require('name="Art_far_forearm"' in rig and 'name="Art_near_forearm"' in rig, "two forearms missing")
    require('name="Art_far_hand"' in rig and 'name="Art_near_hand"' in rig, "two hands missing")
    require(rig.count("visible = false") == 3, "temporary far-arm visibility policy changed")
    require('name="Art_far_thigh"' in rig and 'name="Art_near_thigh"' in rig, "duplicated leg layers missing")
    require('instance=ExtResource("2_rig")' in preview, "preview does not instance M02 rig")
    require('func _sample_ankle' in preview_script, "six-key ankle gait sampler missing")
    require('func _apply_leg_ik' in preview_script, "preview two-bone leg IK missing")
    require('KEY_1' in preview_script and 'KEY_2' in preview_script, "idle/walk preview controls missing")
    require('Vector3(-22.0, 480.0, 0.0)' in preview_script, "balanced measured idle stance missing")
    require('UPPER_REST_ANGLE' in preview_script and 'LOWER_REST_ANGLE' in preview_script, "slanted rest-axis compensation missing")
    require('func _apply_leg_ik' in player_script, "playable two-bone leg IK missing")
    require('Six-frame Kotone walk contract' in player_script, "playable six-frame gait contract missing")
    require('visual_pivot.scale.x = 1.0 if direction > 0.0 else -1.0' in player_script, "direction mirror policy missing")
    require('zoom = Vector2(6, 6)' in player, "world camera zoom changed")
    require('path="res://player/kotone_bot_m01/player.tscn" id="4"' in level, "isolated gate must not replace active M01")
    require('godot --headless --path "$SCRIPT_DIR" --import' in launcher, "fresh-clone texture import pass missing")

    for runtime_asset in ("body_head_pelvis.png", "upper_arm.png", "forearm.png", "hand.png", "thigh.png", "calf.png", "foot.png"):
        require(f'"$ASSET_DIR/{runtime_asset}"' in launcher, f"launcher guard missing: {runtime_asset}")

    require(not (PARTS / "arm_near.png").exists(), "obsolete rigid arm remains in built parts")
    require(not (MODEL / "assets/arm_near.png").exists(), "obsolete rigid arm remains in runtime assets")

    normalized = Image.open(PARTS / "kotone_side_right_normalized.png").convert("RGBA")
    require(normalized.size == (1254, 1254), "normalized side canvas changed")
    require(normalized.getchannel("A").getbbox() == (546, 54, 708, 1165), "normalized side alpha bounds changed")

    for part in manifest["parts"]:
        built = PARTS / part["file"]
        copied = MODEL / "assets" / part["file"]
        require(built.is_file(), f"missing built M02 part: {part['name']}")
        require(copied.is_file(), f"missing copied M02 part: {part['name']}")
        require(sha256(built) == part["sha256"], f"built hash mismatch: {part['name']}")
        require(sha256(copied) == part["sha256"], f"runtime hash mismatch: {part['name']}")
        require(Image.open(built).convert("RGBA").getchannel("A").getbbox() is not None, f"empty alpha: {part['name']}")

    require((PROJECT / "player/player.tscn").is_file(), "gBot reference removed")
    require((PROJECT / "player/kotone_bot_m01/player.tscn").is_file(), "M01 rollback removed")
    require((PROJECT / "player/kotone_bot_m02/player.tscn").is_file(), "current M02 side player removed")
    require(not (MODEL / "neutral_visibility_test.tscn").exists(), "deleted front M02 gate remains")
    require(m03["technical_model"] == "KTN-RC3-M03", "M03 model id changed")
    require(len(m03["assets"]) == 6, "M03 six-part asset set changed")
    require(m03["inherits_art_from"] is None, "M03 inherited M02 art")
    require(not (PROJECT / "player/kotone_bot_m03/player.tscn").exists(), "M03 must not have a runtime scene yet")
    require(not (PROJECT / "m02-neutral-preview.sh").exists(), "deleted front M02 launcher remains")
    print("KTN-RC3-M02 ISOLATED SIDE GAIT STATIC VALIDATION PASSED")


if __name__ == "__main__":
    main()
