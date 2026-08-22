#!/usr/bin/env python3
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "scenes/mannequin/kotone_front_right_arm_anatomical_mesh_spike.tscn"
SOURCE = ROOT / "assets/rc3/mannequin/source/kotone_front_mannequin_t_pose.png"
MANIFEST = ROOT / "assets/rc3/mannequin/mannequin_manifest.json"
RENDERER = ROOT / "scripts/mannequin/render_front_right_arm_anatomical_mesh_spike.gd"
EXPECTED_SHA = "b13044d02fbc96a405e83d7903099e5a6bb9f99a6b471ac9e171c63ffc734b34"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


scene_text = SCENE.read_text(encoding="utf-8")
renderer_text = RENDERER.read_text(encoding="utf-8")
manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
require(hashlib.sha256(SOURCE.read_bytes()).hexdigest() == EXPECTED_SHA, "approved source SHA-256 is unchanged")
require('name="FrontRightArmMesh" type="Polygon2D"' in scene_text, "anatomical Polygon2D is present")
require("internal_vertex_count = 2" in scene_text, "only two internal joint vertices are declared")
weight_arrays = re.findall(r"PackedFloat32Array\(([^)]*)\)", scene_text)
require(len(weight_arrays) == 3, "exactly three bone-weight arrays are declared")
weights = [[float(value.strip()) for value in array.split(",")] for array in weight_arrays]
require(all(len(array) == 24 for array in weights), "each bone has exactly 24 weights")
require(all(value in {0.0, 0.5, 1.0} for array in weights for value in array), "weights are rigid or 50/50 joint shares")
require(all(abs(sum(vertex) - 1.0) < 1e-9 for vertex in zip(*weights)), "every vertex weight sum is one")
require(manifest["current_gate"] == "front_right_elbow_anatomical_mesh_needs_godot_runtime_review", "manifest points to Task 4I runtime gate")
require("func _render_panel(" in renderer_text, "renderer isolates every pose in its own panel viewport")
require("viewport.size = Vector2i(PANEL_WIDTH, HEIGHT)" in renderer_text, "isolated viewport is exactly one panel wide")
require("sheet.blit_rect(" in renderer_text, "renderer stitches completed panel images into the final sheet")
require("ELBOW_PANEL_POSITION := Vector2(286.0, 270.0)" in renderer_text, "renderer anchors the elbow inside the close-up panel")
require("_hide_base_rig_sprites(rig)" in renderer_text, "renderer shows the anatomical arm mesh without full-body sprite clutter")
print("FRONT RIGHT ARM ANATOMICAL MESH SPIKE STATIC VALIDATION PASSED")
