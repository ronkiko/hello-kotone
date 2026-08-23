#!/usr/bin/env python3
"""Static gate for the first operator-observable M03 torso bone."""

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


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    asset_manifest = json.loads((PARTS / "m03_side_asset_manifest.json").read_text(encoding="utf-8"))
    model_manifest = json.loads((MODEL / "model_manifest.json").read_text(encoding="utf-8"))
    rig = (MODEL / "torso_rig.tscn").read_text(encoding="utf-8")
    preview = (MODEL / "torso_preview.tscn").read_text(encoding="utf-8")
    preview_script = (MODEL / "torso_preview.gd").read_text(encoding="utf-8")
    launcher = (PROJECT / "m03-torso-preview.sh").read_text(encoding="utf-8")

    require(model_manifest["technical_model"] == "KTN-RC3-M03", "wrong model id")
    require(model_manifest["status"] == "head_bone_gate_operator_review_required", "wrong gate status")
    require(model_manifest["runtime_scene"] == "torso_rig.tscn", "wrong M03 rig scene")
    require(len(re.findall(r'type="Bone2D"', rig)) == 2, "expected exactly two Bone2D")
    require('[node name="Torso" type="Bone2D" parent="Skeleton2D"]' in rig, "Torso root bone missing")
    require("position = Vector2(0, 0)" in rig, "Torso root must stay at scene origin")
    require('offset = Vector2(-110, -350)' in rig, "torso texture must map its pelvis pivot to the root origin")
    require("auto_calculate_length_and_angle = false" in rig, "Torso bone must use explicit geometry")
    require("rotation = -1.570796" in rig, "Torso transform must point vertically upward")
    require("rest = Transform2D(0, -1, 1, 0, 0, 0)" in rig, "Torso rest must match its vertical transform")
    require("length = 300.0" in rig and "bone_angle = 0.0" in rig, "Torso bone axis changed")
    require('[node name="Art_torso" type="Sprite2D" parent="Skeleton2D/Torso"]' in rig, "torso art is not bound to Torso")
    require("rotation = 1.570796" in rig, "art must counter-rotate the vertical bone transform")
    require('path="res://player/kotone_bot_m03/assets/torso.png"' in rig, "torso texture missing")
    require('[node name="Head" type="Bone2D" parent="Skeleton2D/Torso"]' in rig, "Head bone missing")
    require("position = Vector2(300, 0)" in rig, "Head must attach at the far end of Torso")
    require("rest = Transform2D(0, 1, -1, 0, 300, 0)" in rig, "Head rest must match its attachment transform")
    require('[node name="Art_head" type="Sprite2D" parent="Skeleton2D/Torso/Head"]' in rig, "head art is not bound to Head")
    require('offset = Vector2(-80, -190)' in rig, "head texture neck registration changed")
    require('path="res://player/kotone_bot_m03/assets/head.png"' in rig, "head texture missing")
    require('instance=ExtResource("2_rig")' in preview, "preview does not instance torso rig")
    require("KEY_Q" in preview_script and "KEY_R" in preview_script and "KEY_E" in preview_script, "manual angle controls missing")
    require("HEAD_REST_AXIS" in preview_script and "$Rig/Skeleton2D/Torso/Head" in preview_script, "preview must control Head")
    require('godot --headless --path "$SCRIPT_DIR" --import' in launcher, "fresh-checkout import pass missing")
    require("res://player/kotone_bot_m03/torso_preview.tscn" in launcher, "wrong preview scene")
    require(not (MODEL / "player.tscn").exists(), "M03 must not replace the game player yet")

    for item in asset_manifest["parts"]:
        built = PARTS / item["file"]
        copied = MODEL / "assets" / item["file"]
        require(built.is_file() and copied.is_file(), f"missing M03 asset: {item['name']}")
        require(sha256(built) == item["sha256"], f"built hash mismatch: {item['name']}")
        require(sha256(copied) == item["sha256"], f"runtime hash mismatch: {item['name']}")
        require(Image.open(built).convert("RGBA").getchannel("A").getbbox() is not None, f"empty alpha: {item['name']}")

    print("KTN-RC3-M03 TORSO BONE STATIC VALIDATION PASSED")


if __name__ == "__main__":
    main()
