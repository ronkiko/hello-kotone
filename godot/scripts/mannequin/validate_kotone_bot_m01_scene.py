#!/usr/bin/env python3
"""Static validation for the playable KTN-RC3-M01 scene and map wiring."""

from __future__ import annotations

import re
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / "reference_projects/godot_skeleton2d_demo"
SCENE = PROJECT / "player/kotone_bot_m01/player.tscn"
LEVEL = PROJECT / "level.tscn"
SCRIPT = PROJECT / "player/kotone_bot_m01/player.gd"
ORIGINAL = PROJECT / "player/player.tscn"
MANIFEST = ROOT / "godot/assets/rc3/mannequin/godot_mesh/front/m01/m01_asset_manifest.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def main() -> None:
    scene = SCENE.read_text(encoding="utf-8")
    level = LEVEL.read_text(encoding="utf-8")
    controller = SCRIPT.read_text(encoding="utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    require('[node name="SkeletalPlayer" type="CharacterBody2D"]' in scene, "missing player root")
    require(len(re.findall(r'type="Bone2D"', scene)) == 15, "expected 15 Bone2D nodes")
    require(len(re.findall(r'type="Polygon2D"', scene)) == 6, "expected six Polygon2D regions")
    require(scene.count('skeleton = NodePath("../../Skeleton2D")') == 6, "all polygons must bind the common skeleton")
    require('"Hip/Chest/RightArm/RightForearm/RightHand"' in scene, "right hand binding missing")
    require('"Hip/Chest/LeftArm/LeftForearm/LeftHand"' in scene, "left hand binding missing")
    require('"Hip/RightLeg/RightLowerLeg/RightFoot"' in scene, "right foot binding missing")
    require('"Hip/LeftLeg/LeftLowerLeg/LeftFoot"' in scene, "left foot binding missing")
    require('internal_vertex_count = ' in scene and 'polygons = [' in scene, "custom mesh cells missing")

    for method in ("_apply_idle_pose", "_apply_locomotion_pose", "_apply_air_pose"):
        require(f"func {method}" in controller, f"missing {method}")
    require('move_and_slide()' in controller, "movement controller missing")
    require('visual_pivot.scale.x = 1.0 if direction > 0.0 else -1.0' in controller, "direction flip missing")
    require('[node name="Camera2D" type="Camera2D" parent="."]' in scene, "player camera missing")
    require('position = Vector2(-25.08, -46.56)' in scene, "visual registration changed")
    require('scale = Vector2(0.04, 0.04)' in scene, "gBot-field scale changed")

    for name, asset in manifest["assets"].items():
        copied = PROJECT / f"player/kotone_bot_m01/assets/{name}.png"
        require(copied.is_file(), f"missing copied {name} texture")
        digest = hashlib.sha256(copied.read_bytes()).hexdigest()
        require(digest == asset["sha256"], f"copied {name} texture changed")

    require('path="res://player/kotone_bot_m01/player.tscn" id="4"' in level, "level pointer does not select Kotone-bot")
    require('instance=ExtResource("4")' in level, "level player instance missing")

    require(ORIGINAL.is_file(), "official gBot scene was removed")
    require((PROJECT / "player/player.gd").is_file(), "official gBot controller was removed")
    require((PROJECT / "player/gBot.png").is_file(), "official gBot texture was removed")
    require((PROJECT / "demobot.sh").is_file(), "official gBot launcher was removed")

    print("KTN-RC3-M01 GBOT LEVEL OVERRIDE STATIC VALIDATION PASSED")


if __name__ == "__main__":
    main()
