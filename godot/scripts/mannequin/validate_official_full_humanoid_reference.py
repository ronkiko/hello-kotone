#!/usr/bin/env python3
"""Static contract check for the vendored official Godot Skeleton2D demo."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SCENE = ROOT / "reference_projects/godot_skeleton2d_demo/player/player.tscn"

EXPECTED_POLYGONS = {
    "RightArm": (19, 7, ("Hip/Chest/RightArm", "Hip/Chest/RightArm/RightForearm", "Hip/Chest/RightArm/RightForearm/RightHand")),
    "RightLeg": (14, 5, ("Hip/RightLeg", "Hip/RightLeg/RightLowerLeg", "Hip/RightLeg/RightLowerLeg/RightFoot")),
    "Body": (21, 8, ("Hip", "Hip/Chest")),
    "LeftLeg": (15, 4, ("Hip/LeftLeg", "Hip/LeftLeg/LeftLowerLeg", "Hip/LeftLeg/LeftLowerLeg/LeftFoot")),
    "Head": (14, 1, ("Hip/Chest/Head",)),
    "Chin": (7, 1, ("Hip/Chest/Head/Chin",)),
    "LeftArm": (20, 7, ("Hip/Chest/LeftArm", "Hip/Chest/LeftArm/LeftForearm", "Hip/Chest/LeftArm/LeftForearm/LeftHand")),
}

EXPECTED_BONES = {
    "Hip", "Chest", "Head", "Chin",
    "RightArm", "RightForearm", "RightHand",
    "LeftArm", "LeftForearm", "LeftHand",
    "RightLeg", "RightLowerLeg", "RightFoot",
    "LeftLeg", "LeftLowerLeg", "LeftFoot",
}

EXPECTED_ANIMATIONS = {"fall", "fly", "idle", "jump", "land", "land_hard", "run", "walk"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def property_value(block: str, name: str) -> str:
    match = re.search(rf"^{re.escape(name)} = (.+)$", block, re.MULTILINE)
    require(match is not None, f"missing {name} property")
    return match.group(1)


def main() -> None:
    require(SCENE.is_file(), f"missing vendored scene: {SCENE}")
    text = SCENE.read_text(encoding="utf-8")

    bone_names = set(re.findall(r'^\[node name="([^"]+)" type="Bone2D"', text, re.MULTILINE))
    require(bone_names == EXPECTED_BONES, f"unexpected Bone2D set: {sorted(bone_names)}")

    node_blocks = re.split(r"(?=^\[node )", text, flags=re.MULTILINE)
    polygon_blocks: dict[str, str] = {}
    draw_order: list[str] = []
    for block in node_blocks:
        match = re.match(r'^\[node name="([^"]+)" type="Polygon2D" parent="Sprite2D/Polygons"', block)
        if match:
            name = match.group(1)
            polygon_blocks[name] = block
            draw_order.append(name)

    require(draw_order == list(EXPECTED_POLYGONS), f"unexpected Polygon2D draw order: {draw_order}")

    for name, (vertex_count, cell_count, active_paths) in EXPECTED_POLYGONS.items():
        block = polygon_blocks[name]
        require(property_value(block, "skeleton") == 'NodePath("../../Skeleton2D")', f"{name}: wrong skeleton path")

        point_numbers = re.findall(r"-?\d+(?:\.\d+)?", property_value(block, "polygon"))
        require(len(point_numbers) // 2 == vertex_count, f"{name}: expected {vertex_count} vertices")

        cells = re.findall(r"PackedInt32Array\(([^)]*)\)", property_value(block, "polygons"))
        require(len(cells) == cell_count, f"{name}: expected {cell_count} explicit cells")

        bones = property_value(block, "bones")
        active: list[str] = []
        for match in re.finditer(r'"([^"]+)", PackedFloat32Array\(([^)]*)\)', bones):
            weights = [float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", match.group(2))]
            require(len(weights) == vertex_count, f"{name}: weight count mismatch for {match.group(1)}")
            if any(weight > 0 for weight in weights):
                active.append(match.group(1))
        require(tuple(active) == active_paths, f"{name}: active bone paths differ: {active}")

        internal_count = int(property_value(block, "internal_vertex_count"))
        require(internal_count == vertex_count, f"{name}: unexpected custom-mesh point count")

    animations_match = re.search(
        r'\[sub_resource type="AnimationLibrary"[^]]*\](.*?)(?=\n\[sub_resource|\n\[node)',
        text,
        re.DOTALL,
    )
    require(animations_match is not None, "missing AnimationLibrary")
    animations = set(re.findall(r'&"([^"]+)": SubResource', animations_match.group(1)))
    require(animations == EXPECTED_ANIMATIONS, f"unexpected animation set: {sorted(animations)}")

    print("OFFICIAL FULL HUMANOID REFERENCE STATIC VALIDATION PASSED")
    print("7 Polygon2D regions; 16 Bone2D nodes; 8 whole-body animations")


if __name__ == "__main__":
    main()
