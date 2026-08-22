#!/usr/bin/env python3
"""Generate the KTN-RC3-M01 six-Polygon2D playable scene."""

from __future__ import annotations

import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ASSET_MANIFEST = ROOT / "godot/assets/rc3/mannequin/godot_mesh/front/m01/m01_asset_manifest.json"
TARGET_DIR = ROOT / "reference_projects/godot_skeleton2d_demo/player/kotone_bot_m01"
ASSET_DIR = TARGET_DIR / "assets"
OUTPUT = TARGET_DIR / "player.tscn"

ALL_BONES = [
    "Hip", "Hip/Chest", "Hip/Chest/Head",
    "Hip/Chest/RightArm", "Hip/Chest/RightArm/RightForearm", "Hip/Chest/RightArm/RightForearm/RightHand",
    "Hip/Chest/LeftArm", "Hip/Chest/LeftArm/LeftForearm", "Hip/Chest/LeftArm/LeftForearm/LeftHand",
    "Hip/RightLeg", "Hip/RightLeg/RightLowerLeg", "Hip/RightLeg/RightLowerLeg/RightFoot",
    "Hip/LeftLeg", "Hip/LeftLeg/LeftLowerLeg", "Hip/LeftLeg/LeftLowerLeg/LeftFoot",
]


def fmt_number(value: float) -> str:
    if float(value).is_integer():
        return str(int(value))
    return f"{value:.6f}".rstrip("0").rstrip(".")


def packed_vec(points: list[tuple[float, float]]) -> str:
    return "PackedVector2Array(" + ", ".join(fmt_number(v) for point in points for v in point) + ")"


def packed_int(values: list[int]) -> str:
    return "PackedInt32Array(" + ", ".join(str(value) for value in values) + ")"


def packed_float(values: list[float]) -> str:
    return "PackedFloat32Array(" + ", ".join(fmt_number(value) for value in values) + ")"


def grid(xs: list[float], ys: list[float]) -> tuple[list[tuple[float, float]], list[list[int]]]:
    points = [(x, y) for x in xs for y in ys]
    cells: list[list[int]] = []
    height = len(ys)
    for x_index in range(len(xs) - 1):
        for y_index in range(len(ys) - 1):
            a = x_index * height + y_index
            b = (x_index + 1) * height + y_index
            cells.append([a, b, b + 1, a + 1])
    return points, cells


def weights_by_x(points: list[tuple[float, float]], stations: dict[float, dict[str, float]]) -> dict[str, list[float]]:
    paths = {path for mapping in stations.values() for path in mapping}
    return {path: [stations[x].get(path, 0.0) for x, _ in points] for path in paths}


def weights_by_y(points: list[tuple[float, float]], stations: dict[float, dict[str, float]]) -> dict[str, list[float]]:
    paths = {path for mapping in stations.values() for path in mapping}
    return {path: [stations[y].get(path, 0.0) for _, y in points] for path in paths}


def polygon_node(name: str, texture_id: str, position: list[int], points: list[tuple[float, float]], cells: list[list[int]], active: dict[str, list[float]]) -> str:
    zeros = [0.0] * len(points)
    bones: list[str] = []
    for path in ALL_BONES:
        bones.extend([f'"{path}"', packed_float(active.get(path, zeros))])
    cell_text = ", ".join(packed_int(cell) for cell in cells)
    return f'''[node name="{name}" type="Polygon2D" parent="VisualPivot/Sprite2D/Polygons"]
position = Vector2({position[0]}, {position[1]})
texture = ExtResource("{texture_id}")
skeleton = NodePath("../../Skeleton2D")
polygon = {packed_vec(points)}
uv = {packed_vec(points)}
polygons = [{cell_text}]
bones = [{", ".join(bones)}]
internal_vertex_count = {len(points)}
'''


def main() -> None:
    manifest = json.loads(ASSET_MANIFEST.read_text(encoding="utf-8"))
    assets = manifest["assets"]
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    source_dir = ASSET_MANIFEST.parent
    for name, asset in assets.items():
        shutil.copy2(source_dir / asset["file"], ASSET_DIR / f"{name}.png")

    texture_ids = {
        "arm_right": "2_arm_right", "arm_left": "3_arm_left",
        "leg_right": "4_leg_right", "leg_left": "5_leg_left",
        "body": "6_body", "head": "7_head",
    }

    ext_resources = ['[ext_resource type="Script" path="res://player/kotone_bot_m01/player.gd" id="1_script"]']
    for name, texture_id in texture_ids.items():
        ext_resources.append(
            f'[ext_resource type="Texture2D" path="res://player/kotone_bot_m01/assets/{name}.png" id="{texture_id}"]'
        )

    meshes: dict[str, tuple[list[tuple[float, float]], list[list[int]], dict[str, list[float]]]] = {}

    points, cells = grid([0, 87, 201, 339, 363], [0, 46, 92])
    meshes["arm_right"] = (points, cells, weights_by_x(points, {
        0: {"Hip/Chest/RightArm/RightForearm/RightHand": 1},
        87: {"Hip/Chest/RightArm/RightForearm/RightHand": 0.5, "Hip/Chest/RightArm/RightForearm": 0.5},
        201: {"Hip/Chest/RightArm/RightForearm": 0.5, "Hip/Chest/RightArm": 0.5},
        339: {"Hip/Chest/RightArm": 1}, 363: {"Hip/Chest/RightArm": 1},
    }))
    points, cells = grid([0, 23, 161, 275, 363], [0, 46, 92])
    meshes["arm_left"] = (points, cells, weights_by_x(points, {
        0: {"Hip/Chest/LeftArm": 1}, 23: {"Hip/Chest/LeftArm": 1},
        161: {"Hip/Chest/LeftArm": 0.5, "Hip/Chest/LeftArm/LeftForearm": 0.5},
        275: {"Hip/Chest/LeftArm/LeftForearm": 0.5, "Hip/Chest/LeftArm/LeftForearm/LeftHand": 0.5},
        363: {"Hip/Chest/LeftArm/LeftForearm/LeftHand": 1},
    }))
    points, cells = grid([0, 62.5, 125], [0, 45, 245, 520, 644])
    meshes["leg_right"] = (points, cells, weights_by_y(points, {
        0: {"Hip/RightLeg": 1}, 45: {"Hip/RightLeg": 1},
        245: {"Hip/RightLeg": 0.5, "Hip/RightLeg/RightLowerLeg": 0.5},
        520: {"Hip/RightLeg/RightLowerLeg": 0.5, "Hip/RightLeg/RightLowerLeg/RightFoot": 0.5},
        644: {"Hip/RightLeg/RightLowerLeg/RightFoot": 1},
    }))
    points, cells = grid([0, 62.5, 125], [0, 45, 245, 520, 645])
    meshes["leg_left"] = (points, cells, weights_by_y(points, {
        0: {"Hip/LeftLeg": 1}, 45: {"Hip/LeftLeg": 1},
        245: {"Hip/LeftLeg": 0.5, "Hip/LeftLeg/LeftLowerLeg": 0.5},
        520: {"Hip/LeftLeg/LeftLowerLeg": 0.5, "Hip/LeftLeg/LeftLowerLeg/LeftFoot": 0.5},
        645: {"Hip/LeftLeg/LeftLowerLeg/LeftFoot": 1},
    }))
    points, cells = grid([0, 116.5, 233], [0, 220, 245, 360, 426])
    meshes["body"] = (points, cells, weights_by_y(points, {
        0: {"Hip/Chest": 1}, 220: {"Hip/Chest": 1},
        245: {"Hip/Chest": 0.5, "Hip": 0.5},
        360: {"Hip": 1}, 426: {"Hip": 1},
    }))
    points, cells = grid([0, 82, 164], [0, 98.5, 197])
    meshes["head"] = (points, cells, {"Hip/Chest/Head": [1.0] * len(points)})

    node_header = f'''[gd_scene load_steps=9 format=3]

{chr(10).join(ext_resources)}

[sub_resource type="RectangleShape2D" id="RectangleShape2D_player"]
size = Vector2(22, 44)

[node name="SkeletalPlayer" type="CharacterBody2D"]
collision_mask = 28
floor_max_angle = 0.907571
floor_snap_length = 20.0
safe_margin = 0.2
script = ExtResource("1_script")

[node name="VisualPivot" type="Node2D" parent="."]

[node name="Sprite2D" type="Node2D" parent="VisualPivot"]
position = Vector2(-25.08, -46.56)
scale = Vector2(0.04, 0.04)

[node name="Skeleton2D" type="Skeleton2D" parent="VisualPivot/Sprite2D"]

[node name="Hip" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D"]
position = Vector2(627, 545)
rest = Transform2D(1, 0, 0, 1, 627, 545)

[node name="Chest" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip"]
position = Vector2(0, -115)
rest = Transform2D(1, 0, 0, 1, 0, -115)

[node name="Head" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip/Chest"]
position = Vector2(0, -225)
rest = Transform2D(1, 0, 0, 1, 0, -225)
auto_calculate_length_and_angle = false
length = 40.0

[node name="RightArm" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip/Chest"]
position = Vector2(-75, -186)
rest = Transform2D(1, 0, 0, 1, -75, -186)

[node name="RightForearm" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip/Chest/RightArm"]
position = Vector2(-138, 19)
rest = Transform2D(1, 0, 0, 1, -138, 19)

[node name="RightHand" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip/Chest/RightArm/RightForearm"]
position = Vector2(-114, 7)
rest = Transform2D(1, 0, 0, 1, -114, 7)
auto_calculate_length_and_angle = false
length = 40.0

[node name="LeftArm" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip/Chest"]
position = Vector2(75, -186)
rest = Transform2D(1, 0, 0, 1, 75, -186)

[node name="LeftForearm" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip/Chest/LeftArm"]
position = Vector2(138, 19)
rest = Transform2D(1, 0, 0, 1, 138, 19)

[node name="LeftHand" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip/Chest/LeftArm/LeftForearm"]
position = Vector2(114, 7)
rest = Transform2D(1, 0, 0, 1, 114, 7)
auto_calculate_length_and_angle = false
length = 40.0

[node name="RightLeg" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip"]
position = Vector2(-72, 20)
rest = Transform2D(1, 0, 0, 1, -72, 20)

[node name="RightLowerLeg" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip/RightLeg"]
position = Vector2(0, 200)
rest = Transform2D(1, 0, 0, 1, 0, 200)

[node name="RightFoot" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip/RightLeg/RightLowerLeg"]
position = Vector2(0, 275)
rest = Transform2D(1, 0, 0, 1, 0, 275)
auto_calculate_length_and_angle = false
length = 40.0

[node name="LeftLeg" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip"]
position = Vector2(72, 20)
rest = Transform2D(1, 0, 0, 1, 72, 20)

[node name="LeftLowerLeg" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip/LeftLeg"]
position = Vector2(0, 200)
rest = Transform2D(1, 0, 0, 1, 0, 200)

[node name="LeftFoot" type="Bone2D" parent="VisualPivot/Sprite2D/Skeleton2D/Hip/LeftLeg/LeftLowerLeg"]
position = Vector2(0, 275)
rest = Transform2D(1, 0, 0, 1, 0, 275)
auto_calculate_length_and_angle = false
length = 40.0

[node name="Polygons" type="Node2D" parent="VisualPivot/Sprite2D"]
'''

    order = ["arm_right", "leg_right", "body", "leg_left", "head", "arm_left"]
    node_names = {
        "arm_right": "RightArm", "leg_right": "RightLeg", "body": "Body",
        "leg_left": "LeftLeg", "head": "Head", "arm_left": "LeftArm",
    }
    sections = [node_header]
    for name in order:
        points, cells, active = meshes[name]
        sections.append(polygon_node(node_names[name], texture_ids[name], assets[name]["source_offset"], points, cells, active))

    sections.append('''[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
position = Vector2(0, -22)
shape = SubResource("RectangleShape2D_player")

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(0, -32)
zoom = Vector2(4, 4)
process_callback = 0
''')
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(sections), encoding="utf-8")
    print("KTN-RC3-M01 PLAYABLE SCENE BUILD COMPLETE")


if __name__ == "__main__":
    main()
