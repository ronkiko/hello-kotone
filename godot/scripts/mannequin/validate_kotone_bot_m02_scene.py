#!/usr/bin/env python3
"""Static gate for the playable KTN-RC3-M02 segmented mannequin."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / "reference_projects/godot_skeleton2d_demo"
MODEL = PROJECT / "player/kotone_bot_m02"
SCENE = MODEL / "player.tscn"
SCRIPT = MODEL / "player.gd"
LEVEL = PROJECT / "level.tscn"
PARTS = ROOT / "godot/assets/rc3/mannequin/parts/front"
PARTS_MANIFEST = PARTS / "front_parts_manifest.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def main() -> None:
    scene = SCENE.read_text(encoding="utf-8")
    controller = SCRIPT.read_text(encoding="utf-8")
    level = LEVEL.read_text(encoding="utf-8")
    manifest = json.loads(PARTS_MANIFEST.read_text(encoding="utf-8"))

    require(len(re.findall(r'type="Bone2D"', scene)) == 15, "expected 15 bones")
    require(len(re.findall(r'name="Art_[^"]+" type="Sprite2D"', scene)) == 15, "expected 15 rigid art parts")
    require(len(re.findall(r'name="Joint_[^"]+" type="Polygon2D"', scene)) == 24, "expected 12 two-layer joint caps")
    require('path="res://player/kotone_bot_m01/player.tscn" id="4"' in level, "safe M01 rollback is not active")
    require('func _sample_leg' in controller, "contact-cycle sampler missing")
    require('Contact -> mid-stance -> toe-off -> bent-knee swing -> contact.' in controller, "grounded gait contract missing")
    require('deg_to_rad(left.y * intensity)' in controller, "left knee does not flex toward travel direction")
    require('deg_to_rad(right.y * intensity)' in controller, "right knee does not flex toward travel direction")
    require('collision_mask = 28' in scene and 'floor_snap_length = 20.0' in scene, "tested floor collision contract missing")

    for part in manifest["parts"]:
        copied = MODEL / "assets" / part["file"]
        require(copied.is_file(), f"missing {part['name']}")
        require(hashlib.sha256(copied.read_bytes()).hexdigest() == part["sha256"], f"hash mismatch for {part['name']}")
        px, py = part["pivot_local"]
        snippet = f'name="Art_{part["name"]}" type="Sprite2D"'
        require(snippet in scene, f"scene node missing for {part['name']}")
        require(f'position = Vector2({-px}, {-py})' in scene, f"pivot registration missing for {part['name']}")

    require((PROJECT / "player/player.tscn").is_file(), "gBot reference removed")
    require((PROJECT / "player/kotone_bot_m01/player.tscn").is_file(), "M01 rollback scene removed")
    print("KTN-RC3-M02 DISABLED ISOLATED SCENE STATIC VALIDATION PASSED")


if __name__ == "__main__":
    main()
