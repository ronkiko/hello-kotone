#!/usr/bin/env python3
"""Build the isolated and playable KTN-RC3-M03 side mannequin scenes."""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PARTS_DIR = ROOT / "godot/assets/rc3/mannequin/parts/side/m03"
MANIFEST_PATH = PARTS_DIR / "m03_side_asset_manifest.json"
TARGET = ROOT / "reference_projects/godot_skeleton2d_demo/player/kotone_bot_m03"
ASSETS = TARGET / "assets"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bone(name: str, parent: str, x: int, y: int, terminal: bool = False) -> str:
    terminal_fields = ""
    if terminal:
        terminal_fields = "auto_calculate_length_and_angle = false\nlength = 40.0\nbone_angle = 0.0\n"
    return f'''[node name="{name}" type="Bone2D" parent="{parent}"]
position = Vector2({x}, {y})
rest = Transform2D(1, 0, 0, 1, {x}, {y})
{terminal_fields}'''


def art(name: str, parent: str, resource: str, pivot: list[int], z_index: int) -> str:
    return f'''[node name="Art_{name}" type="Sprite2D" parent="{parent}"]
texture = ExtResource("{resource}")
centered = false
position = Vector2({-pivot[0]}, {-pivot[1]})
z_index = {z_index}
'''


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    parts = {part["name"]: part for part in manifest["parts"]}
    TARGET.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "arm_near.png").unlink(missing_ok=True)

    resources: list[str] = []
    resource_by_name: dict[str, str] = {}
    for index, name in enumerate(["body_head_pelvis", "upper_arm", "forearm", "hand", "thigh", "calf", "foot"], start=1):
        part = parts[name]
        source = PARTS_DIR / part["file"]
        if sha256(source) != part["sha256"]:
            raise SystemExit(f"FAIL: M03 asset hash changed for {name}")
        shutil.copy2(source, ASSETS / part["file"])
        resource_id = f"{index}_{name}"
        resource_by_name[name] = resource_id
        resources.append(
            f'[ext_resource type="Texture2D" path="res://player/kotone_bot_m03/assets/{part["file"]}" id="{resource_id}"]'
        )

    hip_x, hip_y = manifest["pivots"]["hip"]
    shoulder_x, shoulder_y = manifest["pivots"]["shoulder"]
    elbow_x, elbow_y = manifest["pivots"]["elbow"]
    wrist_x, wrist_y = manifest["pivots"]["wrist"]
    knee_x, knee_y = manifest["pivots"]["knee"]
    ankle_x, ankle_y = manifest["pivots"]["ankle"]

    rig_lines = [f'''[gd_scene load_steps=8 format=3]

{chr(10).join(resources)}

[node name="M03SideRig" type="Node2D"]

[node name="Skeleton2D" type="Skeleton2D" parent="."]
''']
    rig_lines.extend([
        bone("Hip", "Skeleton2D", hip_x, hip_y),
        bone("FarLeg", "Skeleton2D/Hip", 0, 0),
        bone("FarLower", "Skeleton2D/Hip/FarLeg", knee_x - hip_x, knee_y - hip_y),
        bone("FarFoot", "Skeleton2D/Hip/FarLeg/FarLower", ankle_x - knee_x, ankle_y - knee_y, True),
        bone("NearLeg", "Skeleton2D/Hip", 0, 0),
        bone("NearLower", "Skeleton2D/Hip/NearLeg", knee_x - hip_x, knee_y - hip_y),
        bone("NearFoot", "Skeleton2D/Hip/NearLeg/NearLower", ankle_x - knee_x, ankle_y - knee_y, True),
        bone("ArmFarUpper", "Skeleton2D/Hip", shoulder_x - hip_x, shoulder_y - hip_y),
        bone("ArmFarLower", "Skeleton2D/Hip/ArmFarUpper", elbow_x - shoulder_x, elbow_y - shoulder_y),
        bone("ArmFarHand", "Skeleton2D/Hip/ArmFarUpper/ArmFarLower", wrist_x - elbow_x, wrist_y - elbow_y, True),
        bone("ArmNearUpper", "Skeleton2D/Hip", shoulder_x - hip_x, shoulder_y - hip_y),
        bone("ArmNearLower", "Skeleton2D/Hip/ArmNearUpper", elbow_x - shoulder_x, elbow_y - shoulder_y),
        bone("ArmNearHand", "Skeleton2D/Hip/ArmNearUpper/ArmNearLower", wrist_x - elbow_x, wrist_y - elbow_y, True),
    ])
    rig_lines.extend([
        art("far_upper_arm", "Skeleton2D/Hip/ArmFarUpper", resource_by_name["upper_arm"], parts["upper_arm"]["pivot_local"], 0),
        art("far_forearm", "Skeleton2D/Hip/ArmFarUpper/ArmFarLower", resource_by_name["forearm"], parts["forearm"]["pivot_local"], 0),
        art("far_hand", "Skeleton2D/Hip/ArmFarUpper/ArmFarLower/ArmFarHand", resource_by_name["hand"], parts["hand"]["pivot_local"], 0),
        art("far_thigh", "Skeleton2D/Hip/FarLeg", resource_by_name["thigh"], parts["thigh"]["pivot_local"], 1),
        art("far_calf", "Skeleton2D/Hip/FarLeg/FarLower", resource_by_name["calf"], parts["calf"]["pivot_local"], 2),
        art("far_foot", "Skeleton2D/Hip/FarLeg/FarLower/FarFoot", resource_by_name["foot"], parts["foot"]["pivot_local"], 3),
        art("body_head_pelvis", "Skeleton2D/Hip", resource_by_name["body_head_pelvis"], parts["body_head_pelvis"]["pivot_local"], 4),
        art("near_thigh", "Skeleton2D/Hip/NearLeg", resource_by_name["thigh"], parts["thigh"]["pivot_local"], 5),
        art("near_calf", "Skeleton2D/Hip/NearLeg/NearLower", resource_by_name["calf"], parts["calf"]["pivot_local"], 6),
        art("near_foot", "Skeleton2D/Hip/NearLeg/NearLower/NearFoot", resource_by_name["foot"], parts["foot"]["pivot_local"], 7),
        art("near_upper_arm", "Skeleton2D/Hip/ArmNearUpper", resource_by_name["upper_arm"], parts["upper_arm"]["pivot_local"], 8),
        art("near_forearm", "Skeleton2D/Hip/ArmNearUpper/ArmNearLower", resource_by_name["forearm"], parts["forearm"]["pivot_local"], 9),
        art("near_hand", "Skeleton2D/Hip/ArmNearUpper/ArmNearLower/ArmNearHand", resource_by_name["hand"], parts["hand"]["pivot_local"], 10),
    ])
    (TARGET / "neutral_rig.tscn").write_text("\n".join(rig_lines), encoding="utf-8")

    (TARGET / "preview.tscn").write_text(
        '''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://player/kotone_bot_m03/preview.gd" id="1_script"]
[ext_resource type="PackedScene" path="res://player/kotone_bot_m03/neutral_rig.tscn" id="2_rig"]

[node name="M03SideAnimatedPreview" type="Node2D"]
script = ExtResource("1_script")

[node name="Background" type="ColorRect" parent="."]
offset_right = 1920.0
offset_bottom = 1080.0
mouse_filter = 2
color = Color(0.18, 0.20, 0.24, 1)
z_index = -100

[node name="Instruction" type="Label" parent="."]
offset_left = 24.0
offset_top = 20.0
offset_right = 1500.0
offset_bottom = 56.0
text = "KTN-RC3-M03 SIDE GAIT GATE — expected: measured shoulder/elbow/wrist chains"
theme_override_font_sizes/font_size = 22
z_index = 100

[node name="Rig" parent="." instance=ExtResource("2_rig")]
position = Vector2(458, 80)
scale = Vector2(0.8, 0.8)
''',
        encoding="utf-8",
    )

    (TARGET / "player.tscn").write_text(
        '''[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://player/kotone_bot_m03/player.gd" id="1_script"]
[ext_resource type="PackedScene" path="res://player/kotone_bot_m03/neutral_rig.tscn" id="2_rig"]

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

[node name="Rig" parent="VisualPivot/Sprite2D" instance=ExtResource("2_rig")]

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
position = Vector2(0, -22)
shape = SubResource("RectangleShape2D_player")

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(0, -32)
zoom = Vector2(6, 6)
process_callback = 0
''',
        encoding="utf-8",
    )

    runtime_manifest = dict(manifest)
    runtime_manifest["status"] = "isolated_animated_preview_ready"
    runtime_manifest["asset_manifest"] = "../../../../../godot/assets/rc3/mannequin/parts/side/m03/m03_side_asset_manifest.json"
    (TARGET / "model_manifest.json").write_text(
        json.dumps(runtime_manifest, indent=2) + "\n",
        encoding="utf-8",
    )
    print("KTN-RC3-M03 SIDE SCENES BUILD COMPLETE")


if __name__ == "__main__":
    main()
