#!/usr/bin/env python3
"""Build KTN-RC3-M02 as a rigid cutout mannequin with explicit joint caps."""

from __future__ import annotations

import hashlib
import json
import math
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / "godot/assets/rc3/mannequin/parts/front"
MANIFEST = SOURCE_DIR / "front_parts_manifest.json"
TARGET = ROOT / "reference_projects/godot_skeleton2d_demo/player/kotone_bot_m02"
ASSETS = TARGET / "assets"
OUTPUT = TARGET / "player.tscn"

BONES = [
    ("Hip", "VisualPivot/Sprite2D/Skeleton2D", (627, 545)),
    ("Chest", "VisualPivot/Sprite2D/Skeleton2D/Hip", (0, -115)),
    ("Head", "VisualPivot/Sprite2D/Skeleton2D/Hip/Chest", (0, -225)),
    ("RightArm", "VisualPivot/Sprite2D/Skeleton2D/Hip/Chest", (-75, -186)),
    ("RightForearm", "VisualPivot/Sprite2D/Skeleton2D/Hip/Chest/RightArm", (-138, 19)),
    ("RightHand", "VisualPivot/Sprite2D/Skeleton2D/Hip/Chest/RightArm/RightForearm", (-114, 7)),
    ("LeftArm", "VisualPivot/Sprite2D/Skeleton2D/Hip/Chest", (75, -186)),
    ("LeftForearm", "VisualPivot/Sprite2D/Skeleton2D/Hip/Chest/LeftArm", (138, 19)),
    ("LeftHand", "VisualPivot/Sprite2D/Skeleton2D/Hip/Chest/LeftArm/LeftForearm", (114, 7)),
    ("RightLeg", "VisualPivot/Sprite2D/Skeleton2D/Hip", (-72, 20)),
    ("RightLowerLeg", "VisualPivot/Sprite2D/Skeleton2D/Hip/RightLeg", (0, 200)),
    ("RightFoot", "VisualPivot/Sprite2D/Skeleton2D/Hip/RightLeg/RightLowerLeg", (0, 275)),
    ("LeftLeg", "VisualPivot/Sprite2D/Skeleton2D/Hip", (72, 20)),
    ("LeftLowerLeg", "VisualPivot/Sprite2D/Skeleton2D/Hip/LeftLeg", (0, 200)),
    ("LeftFoot", "VisualPivot/Sprite2D/Skeleton2D/Hip/LeftLeg/LeftLowerLeg", (0, 275)),
]

PART_BONES = {
    "head_neck": "Hip/Chest/Head",
    "torso": "Hip/Chest",
    "pelvis": "Hip",
    "upper_arm_right": "Hip/Chest/RightArm",
    "forearm_right": "Hip/Chest/RightArm/RightForearm",
    "hand_right": "Hip/Chest/RightArm/RightForearm/RightHand",
    "upper_arm_left": "Hip/Chest/LeftArm",
    "forearm_left": "Hip/Chest/LeftArm/LeftForearm",
    "hand_left": "Hip/Chest/LeftArm/LeftForearm/LeftHand",
    "thigh_right": "Hip/RightLeg",
    "calf_right": "Hip/RightLeg/RightLowerLeg",
    "foot_right": "Hip/RightLeg/RightLowerLeg/RightFoot",
    "thigh_left": "Hip/LeftLeg",
    "calf_left": "Hip/LeftLeg/LeftLowerLeg",
    "foot_left": "Hip/LeftLeg/LeftLowerLeg/LeftFoot",
}

CAPS = [
    ("ShoulderRight", "Hip/Chest/RightArm", 23),
    ("ElbowRight", "Hip/Chest/RightArm/RightForearm", 15),
    ("WristRight", "Hip/Chest/RightArm/RightForearm/RightHand", 10),
    ("ShoulderLeft", "Hip/Chest/LeftArm", 23),
    ("ElbowLeft", "Hip/Chest/LeftArm/LeftForearm", 15),
    ("WristLeft", "Hip/Chest/LeftArm/LeftForearm/LeftHand", 10),
    ("HipRight", "Hip/RightLeg", 25),
    ("KneeRight", "Hip/RightLeg/RightLowerLeg", 20),
    ("AnkleRight", "Hip/RightLeg/RightLowerLeg/RightFoot", 12),
    ("HipLeft", "Hip/LeftLeg", 25),
    ("KneeLeft", "Hip/LeftLeg/LeftLowerLeg", 20),
    ("AnkleLeft", "Hip/LeftLeg/LeftLowerLeg/LeftFoot", 12),
]


def circle(radius: float, count: int = 20) -> str:
    values: list[str] = []
    for index in range(count):
        angle = math.tau * index / count
        values.extend((f"{math.cos(angle) * radius:.4f}", f"{math.sin(angle) * radius:.4f}"))
    return "PackedVector2Array(" + ", ".join(values) + ")"


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    parts = {part["name"]: part for part in manifest["parts"]}
    order = manifest["layer_order_back_to_front"]
    ASSETS.mkdir(parents=True, exist_ok=True)

    resources = ['[ext_resource type="Script" path="res://player/kotone_bot_m02/player.gd" id="1_script"]']
    for index, name in enumerate(order, start=2):
        source = SOURCE_DIR / parts[name]["file"]
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if digest != parts[name]["sha256"]:
            raise SystemExit(f"FAIL: source hash changed for {name}")
        shutil.copy2(source, ASSETS / parts[name]["file"])
        resources.append(
            f'[ext_resource type="Texture2D" path="res://player/kotone_bot_m02/assets/{parts[name]["file"]}" id="{index}_{name}"]'
        )

    lines = [f'''[gd_scene load_steps=18 format=3]

{chr(10).join(resources)}

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
''']

    for name, parent, position in BONES:
        lines.append(f'''[node name="{name}" type="Bone2D" parent="{parent}"]
position = Vector2({position[0]}, {position[1]})
rest = Transform2D(1, 0, 0, 1, {position[0]}, {position[1]})
''')

    for z_index, name in enumerate(order):
        part = parts[name]
        pivot_x, pivot_y = part["pivot_local"]
        parent = "VisualPivot/Sprite2D/Skeleton2D/" + PART_BONES[name]
        resource_id = f"{z_index + 2}_{name}"
        lines.append(f'''[node name="Art_{name}" type="Sprite2D" parent="{parent}"]
texture = ExtResource("{resource_id}")
centered = false
position = Vector2({-pivot_x}, {-pivot_y})
z_index = {z_index}
''')

    for index, (name, bone_path, radius) in enumerate(CAPS):
        parent = "VisualPivot/Sprite2D/Skeleton2D/" + bone_path
        lines.append(f'''[node name="Joint_{name}_Outer" type="Polygon2D" parent="{parent}"]
polygon = {circle(radius)}
color = Color(0.49, 0.30, 0.27, 1)
z_index = {30 + index * 2}

[node name="Joint_{name}_Inner" type="Polygon2D" parent="{parent}"]
polygon = {circle(radius - 3)}
color = Color(0.96, 0.72, 0.60, 1)
z_index = {31 + index * 2}
''')

    lines.append('''[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
position = Vector2(0, -22)
shape = SubResource("RectangleShape2D_player")

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(0, -32)
zoom = Vector2(4, 4)
process_callback = 0
''')

    OUTPUT.write_text("\n".join(lines), encoding="utf-8")
    print("KTN-RC3-M02 CUTOUT SCENE BUILD COMPLETE")


if __name__ == "__main__":
    main()
