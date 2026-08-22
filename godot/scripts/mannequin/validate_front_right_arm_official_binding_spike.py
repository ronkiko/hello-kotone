#!/usr/bin/env python3
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "scenes/mannequin/kotone_front_right_arm_official_binding_spike.tscn"
TASK4I_SCENE = ROOT / "scenes/mannequin/kotone_front_right_arm_anatomical_mesh_spike.tscn"
SOURCE = ROOT / "assets/rc3/mannequin/source/kotone_front_mannequin_t_pose.png"
MANIFEST = ROOT / "assets/rc3/mannequin/mannequin_manifest.json"
RENDERER = ROOT / "scripts/mannequin/render_front_right_arm_official_binding_spike.gd"
EXPECTED_SHA = "b13044d02fbc96a405e83d7903099e5a6bb9f99a6b471ac9e171c63ffc734b34"
EXPECTED_BONE_PATHS = [
    "pelvis/torso/upper_arm_right",
    "pelvis/torso/upper_arm_right/forearm_right",
    "pelvis/torso/upper_arm_right/forearm_right/hand_right",
]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


scene_text = SCENE.read_text(encoding="utf-8")
task4i_text = TASK4I_SCENE.read_text(encoding="utf-8")
renderer_text = RENDERER.read_text(encoding="utf-8")
manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
require(hashlib.sha256(SOURCE.read_bytes()).hexdigest() == EXPECTED_SHA, "approved source SHA-256 is unchanged")
require('skeleton = NodePath("../BaseRig/Skeleton2D")' in scene_text, "Polygon2D locates the accepted Skeleton2D")
bone_paths = re.findall(r'"(pelvis/torso/upper_arm_right[^"]*)", PackedFloat32Array', scene_text)
require(bone_paths == EXPECTED_BONE_PATHS, "bone entries are paths inside Skeleton2D")
require('"../BaseRig/Skeleton2D/pelvis/' not in scene_text, "rejected polygon-relative bone paths are absent")
weight_arrays = re.findall(r"PackedFloat32Array\(([^)]*)\)", scene_text)
task4i_weight_arrays = re.findall(r"PackedFloat32Array\(([^)]*)\)", task4i_text)
require(len(weight_arrays) == 3, "exactly three bone-weight arrays are declared")
require(weight_arrays == task4i_weight_arrays, "Task 4J changes no Task 4I weight values")
weights = [[float(value.strip()) for value in array.split(",")] for array in weight_arrays]
require(all(len(array) == 24 for array in weights), "each bone has exactly 24 weights")
require(all(value in {0.0, 0.5, 1.0} for array in weights for value in array), "weights remain unchanged and joint-local")
require(all(abs(sum(vertex) - 1.0) < 1e-9 for vertex in zip(*weights)), "every vertex weight sum is one")
for property_name in ("polygon", "uv", "polygons"):
    pattern = rf"^{property_name} = .+$"
    require(
        re.search(pattern, scene_text, re.MULTILINE).group(0)
        == re.search(pattern, task4i_text, re.MULTILINE).group(0),
        f"Task 4J retains Task 4I {property_name}",
    )
require("_panel_contains_arm_mesh" in renderer_text, "renderer rejects an empty arm viewport")
require(manifest["current_gate"] == "front_right_arm_official_binding_needs_godot_runtime_review", "manifest points to Task 4J runtime gate")
print("FRONT RIGHT ARM OFFICIAL BINDING SPIKE STATIC VALIDATION PASSED")
