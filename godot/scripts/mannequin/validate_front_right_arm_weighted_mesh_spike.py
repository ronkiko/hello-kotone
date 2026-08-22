#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "scenes/mannequin/kotone_front_right_arm_weighted_mesh_spike.tscn"
SOURCE = ROOT / "assets/rc3/mannequin/source/kotone_front_mannequin_t_pose.png"
MANIFEST = ROOT / "assets/rc3/mannequin/mannequin_manifest.json"
EXPECTED_SHA = "b13044d02fbc96a405e83d7903099e5a6bb9f99a6b471ac9e171c63ffc734b34"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


scene_text = SCENE.read_text(encoding="utf-8")
manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
require(hashlib.sha256(SOURCE.read_bytes()).hexdigest() == EXPECTED_SHA, "approved source SHA-256 is unchanged")
require('name="FrontRightArmMesh" type="Polygon2D"' in scene_text, "weighted Polygon2D is present")
require('internal_vertex_count = 15' in scene_text, "internal mesh vertices are declared")
require(scene_text.count("PackedFloat32Array(") == 3, "exactly three bone-weight arrays are declared")
require("upper_arm_right/forearm_right/hand_right" in scene_text, "hand bone path is present")
require(manifest["current_gate"] == "front_right_elbow_weighted_mesh_spike_needs_godot_runtime_review", "manifest points to the weighted elbow runtime gate")
print("FRONT RIGHT ARM WEIGHTED MESH SPIKE STATIC VALIDATION PASSED")
