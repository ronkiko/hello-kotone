#!/usr/bin/env python3
"""Static contract checks for the Task 4F full neutral cutout rig."""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path


GODOT_ROOT = Path(__file__).resolve().parents[2]
SCENE = GODOT_ROOT / "scenes/mannequin/kotone_front_neutral_rig.tscn"
PARTS_MANIFEST = GODOT_ROOT / "assets/rc3/mannequin/parts/front/front_parts_manifest.json"

BONES = {
    "pelvis": ("Skeleton2D", (627, 545)),
    "torso": ("Skeleton2D/pelvis", (0, -115)),
    "head_neck": ("Skeleton2D/pelvis/torso", (0, -225)),
    "upper_arm_right": ("Skeleton2D/pelvis/torso", (-75, -186)),
    "forearm_right": ("Skeleton2D/pelvis/torso/upper_arm_right", (-138, 19)),
    "hand_right": ("Skeleton2D/pelvis/torso/upper_arm_right/forearm_right", (-114, 7)),
    "upper_arm_left": ("Skeleton2D/pelvis/torso", (75, -186)),
    "forearm_left": ("Skeleton2D/pelvis/torso/upper_arm_left", (138, 19)),
    "hand_left": ("Skeleton2D/pelvis/torso/upper_arm_left/forearm_left", (114, 7)),
    "hip_right": ("Skeleton2D/pelvis", (-72, 20)),
    "knee_right": ("Skeleton2D/pelvis/hip_right", (0, 200)),
    "ankle_right": ("Skeleton2D/pelvis/hip_right/knee_right", (0, 275)),
    "hip_left": ("Skeleton2D/pelvis", (72, 20)),
    "knee_left": ("Skeleton2D/pelvis/hip_left", (0, 200)),
    "ankle_left": ("Skeleton2D/pelvis/hip_left/knee_left", (0, 275)),
}

SPRITES = {
    "Pelvis": ("Skeleton2D/pelvis", (-115, -140), 12),
    "Torso": ("Skeleton2D/pelvis/torso", (-116, -245), 13),
    "HeadNeck": ("Skeleton2D/pelvis/torso/head_neck", (-82, -151), 14),
    "UpperArmRight": ("Skeleton2D/pelvis/torso/upper_arm_right", (-187, -25), 2),
    "ForearmRight": ("Skeleton2D/pelvis/torso/upper_arm_right/forearm_right", (-154, -23), 1),
    "HandRight": ("Skeleton2D/pelvis/torso/upper_arm_right/forearm_right/hand_right", (-87, -19), 0),
    "UpperArmLeft": ("Skeleton2D/pelvis/torso/upper_arm_left", (-23, -25), 5),
    "ForearmLeft": ("Skeleton2D/pelvis/torso/upper_arm_left/forearm_left", (-31, -23), 4),
    "HandLeft": ("Skeleton2D/pelvis/torso/upper_arm_left/forearm_left/hand_left", (-30, -20), 3),
    "ThighRight": ("Skeleton2D/pelvis/hip_right", (-43, -45), 8),
    "CalfRight": ("Skeleton2D/pelvis/hip_right/knee_right", (-44, -55), 7),
    "FootRight": ("Skeleton2D/pelvis/hip_right/knee_right/ankle_right", (-41, -40), 6),
    "ThighLeft": ("Skeleton2D/pelvis/hip_left", (-80, -45), 11),
    "CalfLeft": ("Skeleton2D/pelvis/hip_left/knee_left", (-36, -55), 10),
    "FootLeft": ("Skeleton2D/pelvis/hip_left/knee_left/ankle_left", (-14, -40), 9),
}


def main() -> None:
    subprocess.run(
        ["python3", str(GODOT_ROOT / "scripts/mannequin/validate_front_parts.py")],
        check=True,
    )
    scene = SCENE.read_text()
    manifest = json.loads(PARTS_MANIFEST.read_text())

    assert scene.count('type="Bone2D"') == 15, "expected exactly 15 Bone2D nodes"
    assert scene.count('type="Sprite2D"') == 15, "expected exactly 15 Sprite2D nodes"
    assert scene.count("centered = false") == 15, "all sprites must use manifest top-left offsets"
    for part in manifest["parts"]:
        path = f'res://assets/rc3/mannequin/parts/front/{part["file"]}'
        assert path in scene, f'missing approved texture: {path}'
    for name, (parent, position) in BONES.items():
        header = f'[node name="{name}" type="Bone2D" parent="{parent}"]'
        assert header in scene, f'missing bone contract: {header}'
        start = scene.index(header)
        section = scene[start : scene.find("\n[node ", start + 1) if "\n[node " in scene[start + 1 :] else None]
        expected = f"position = Vector2({position[0]}, {position[1]})"
        assert expected in section, f'{name} must use local pivot {position}'
    for name, (parent, position, z_index) in SPRITES.items():
        header = f'[node name="{name}" type="Sprite2D" parent="{parent}"]'
        assert header in scene, f'missing sprite contract: {header}'
        start = scene.index(header)
        end = scene.find("\n[node ", start + 1)
        section = scene[start : end if end >= 0 else None]
        assert f"position = Vector2({position[0]}, {position[1]})" in section, f'{name} registration changed'
        assert f"z_index = {z_index}" in section, f'{name} layer changed'
        assert "centered = false" in section, f'{name} must use top-left registration'

    for prohibited in ('type="Polygon2D"', 'type="AnimationPlayer"', "rotation =", "scale ="):
        assert prohibited not in scene, f"neutral rig must not contain {prohibited}"
    print("PASS: 15 approved parts, 15 neutral bones and manifest pivots are present")
    print("PASS: all sprite registrations and back-to-front layers match the approved manifest")
    print("PASS: no mesh, animation, rotation or scale proxy is present")
    print("FRONT NEUTRAL RIG STATIC VALIDATION PASSED")


if __name__ == "__main__":
    main()
