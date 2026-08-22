#!/usr/bin/env python3
"""Static contract checks for Task 4G controlled front articulation."""

from __future__ import annotations

import subprocess
from pathlib import Path


GODOT_ROOT = Path(__file__).resolve().parents[2]
RENDERER = GODOT_ROOT / "scripts/mannequin/render_front_articulation_spike.gd"
VALIDATOR = GODOT_ROOT / "scripts/mannequin/validate_front_articulation_spike.gd"


def main() -> None:
    subprocess.run(
        ["python3", str(GODOT_ROOT / "scripts/mannequin/validate_front_neutral_rig.py")],
        check=True,
    )
    renderer = RENDERER.read_text()
    validator = VALIDATOR.read_text()
    required_renderer_lines = [
        'upper_arm_right") as Bone2D).rotation = deg_to_rad(-12.0)',
        'upper_arm_left") as Bone2D).rotation = deg_to_rad(12.0)',
        'forearm_right") as Bone2D).rotation = deg_to_rad(-18.0)',
        'forearm_left") as Bone2D).rotation = deg_to_rad(18.0)',
        'hip_right") as Bone2D).rotation = deg_to_rad(4.0)',
        'hip_left") as Bone2D).rotation = deg_to_rad(-4.0)',
    ]
    for line in required_renderer_lines:
        assert line in renderer, f"missing controlled pose contract: {line}"
    assert "knee_" not in renderer, "renderer must not rotate or address knees"
    assert "ankle_" not in renderer, "renderer must not rotate or address ankles"
    assert 'type="AnimationPlayer"' not in renderer, "Task 4G is not animation authoring"
    assert "viewer-left" in validator and "viewer-right" in validator, "runtime validator must check screen-space directions"
    assert "LOCKED_PATHS" in validator and "scale.is_equal_approx(Vector2.ONE)" in validator, "knees and ankles must be runtime-locked"
    print("PASS: renderer contains only the six approved in-plane joint rotations")
    print("PASS: runtime contract checks direction and locks knee/ankle rotation and scale")
    print("FRONT ARTICULATION SPIKE STATIC VALIDATION PASSED")


if __name__ == "__main__":
    main()
