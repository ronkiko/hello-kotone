# Task 4H: anatomical-right arm weighted-mesh diagnostic

> Status: diagnostic evidence only. The broad 45-vertex strip is not the
> production topology. Task 4I replaces it with joint-local semantic cells and
> weights based on the official Godot Skeleton2D example.

## Why this spike exists

Task 4G proved the bone directions but rejected rigid PNG cutouts for exposed
joints. At 18 degrees the proximal rectangular ends of both forearm sprites
became visible. Reducing the angle would only hide the defect.

Godot's documented 2D skeletal workflow uses a `Polygon2D` bound to a
`Skeleton2D`, internal vertices, explicit mesh polygons and per-bone weights.
See the official [2D skeletons documentation](https://docs.godotengine.org/en/stable/tutorials/animation/2d_skeletons.html)
and [Polygon2D class reference](https://docs.godotengine.org/en/stable/classes/class_polygon2d.html).
The documentation page may lag the installed 4.7 editor, so this repository
requires a runtime spike rather than assuming compatibility.

## Scope

This spike changes only the anatomical-right arm (viewer-left). It reuses the
accepted Task 4F neutral rig and hides its three rigid right-arm sprites at
runtime. One continuous 45-vertex `Polygon2D` samples the approved full
mannequin T-pose texture. Fifteen internal centerline vertices and 28 explicit
cells support deformation. Weights blend across a 60-pixel elbow zone and a
50-pixel wrist zone.

The accepted source image, neutral rig, left arm, legs and pivots are not
modified. This is not the final full rig, not an animation and not a walk.

## Static check

From the repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 \
  python3 godot/scripts/mannequin/validate_front_right_arm_weighted_mesh_spike.py
```

## Godot 4.7.2 runtime check

From `godot/`:

```bash
godot --headless --path . --editor --quit
godot --headless --path . \
  --script res://scripts/mannequin/validate_front_right_arm_weighted_mesh_spike.gd
xvfb-run -a godot --path . \
  --script res://scripts/mannequin/render_front_right_arm_weighted_mesh_spike.gd
```

Expected validator terminator:

```text
FRONT RIGHT ARM WEIGHTED MESH SPIKE GODOT VALIDATION PASSED
```

The renderer must produce light, dark and magenta A/B/C sheets. Review the
18-degree weighted elbow against the rigid 18-degree failure. Acceptance
requires no rectangular protrusion, no hole, no doubled contour and a smooth
continuous elbow silhouette. Stop after recording the evidence; do not convert
the other limbs yet.
