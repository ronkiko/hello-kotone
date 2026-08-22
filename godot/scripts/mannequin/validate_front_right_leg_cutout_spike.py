#!/usr/bin/env python3
"""Static contract checks for Task 4E before Godot runtime verification."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path


GODOT_ROOT = Path(__file__).resolve().parents[2]
SCENE = GODOT_ROOT / "scenes/mannequin/kotone_front_right_leg_cutout_spike.tscn"


def require(text: str, pattern: str, message: str) -> None:
    assert re.search(pattern, text, flags=re.MULTILINE), message
    print(f"PASS: {message}")


def main() -> None:
    subprocess.run(
        ["python3", str(GODOT_ROOT / "scripts/mannequin/validate_front_parts.py")],
        check=True,
    )
    text = SCENE.read_text()
    require(text, r'path="res://assets/rc3/mannequin/parts/front/pelvis\.png"', "approved pelvis texture is used")
    require(text, r'path="res://assets/rc3/mannequin/parts/front/thigh_right\.png"', "approved right thigh texture is used")
    require(text, r'path="res://assets/rc3/mannequin/parts/front/calf_right\.png"', "approved right calf texture is used")
    require(text, r'path="res://assets/rc3/mannequin/parts/front/foot_right\.png"', "approved right foot texture is used")
    require(text, r'\[node name="pelvis" type="Bone2D" parent="Skeleton2D"\]', "pelvis root bone exists")
    require(text, r'\[node name="hip_right" type="Bone2D" parent="Skeleton2D/pelvis"\]', "hip_right is parented to pelvis")
    require(text, r'\[node name="knee_right" type="Bone2D" parent="Skeleton2D/pelvis/hip_right"\]', "knee_right is parented to hip_right")
    require(text, r'\[node name="ankle_right" type="Bone2D" parent="Skeleton2D/pelvis/hip_right/knee_right"\]', "ankle_right is parented to knee_right")
    require(text, r'position = Vector2\(-72, 20\)', "hip pivot resolves to global (555,565)")
    require(text, r'position = Vector2\(0, 200\)', "knee pivot resolves to global (555,765)")
    require(text, r'position = Vector2\(0, 275\)', "ankle pivot resolves to global (555,1040)")
    assert 'type="Polygon2D"' not in text, "Task 4E must remain a rigid cutout spike"
    assert "scale =" not in text, "Task 4E must not telescope any limb"
    renderer = (GODOT_ROOT / "scripts/mannequin/render_front_right_leg_cutout_spike.py").read_text()
    assert "(-4.0" in renderer and "(4.0" in renderer, "expected limited +/-4 degree hip range"
    assert "knee" not in renderer.lower(), "static renderer must not bend the front-view knee"
    godot_renderer = (GODOT_ROOT / "scripts/mannequin/render_front_right_leg_cutout_spike.gd").read_text()
    assert "HIP_ANGLES := [-4.0, 0.0, 4.0]" in godot_renderer, "Godot QA must use the same small hip range"
    assert 'get_node("Skeleton2D/pelvis/hip_right")' in godot_renderer, "Godot QA must rotate only hip_right"
    assert "knee.rotation" not in godot_renderer, "Godot QA must not rotate the front-view knee"
    print("PASS: no Polygon2D, scaling or front-view knee bend is used")
    print("FRONT RIGHT LEG CUTOUT SPIKE STATIC VALIDATION PASSED")


if __name__ == "__main__":
    main()
