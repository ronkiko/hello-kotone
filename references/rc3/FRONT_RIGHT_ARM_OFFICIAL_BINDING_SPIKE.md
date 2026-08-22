# Task 4J: official Skeleton2D binding spike

## Purpose

Task 4I is rejected because all of its visual passes were invalid and its
`Polygon2D.bones` entries used paths from the polygon to the bones. The
official Godot 4.7 Skeleton2D Demo instead serializes each bone entry as a path
inside the `Skeleton2D` selected by the polygon's `skeleton` property.

Task 4J changes only that binding contract. It deliberately retains the Task
4I texture, 24 vertices, 18 cells and weight arrays so a successful render can
be attributed to the corrected paths rather than a simultaneous topology
change.

Official reference:

- `../../reference_projects/godot_skeleton2d_demo/player/player.tscn`;
- https://github.com/godotengine/godot-demo-projects/tree/master/2d/skeleton.

## Verification

From the repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 \
  python3 godot/scripts/mannequin/validate_front_right_arm_official_binding_spike.py
```

From `godot/` with Godot 4.7.2:

```bash
godot --headless --path . --editor --quit
godot --headless --path . \
  --script res://scripts/mannequin/validate_front_right_arm_official_binding_spike.gd
xvfb-run -a godot --path . \
  --script res://scripts/mannequin/render_front_right_arm_official_binding_spike.gd
```

Expected terminators:

```text
FRONT RIGHT ARM OFFICIAL BINDING SPIKE GODOT VALIDATION PASSED
RENDER COMPLETE: 3 Task 4J previews with visible arm mesh
```

The renderer rejects a panel when the arm region contains only its background.
Therefore an exit code of zero proves that all twelve arm panels contain
rasterized content; visual review still decides whether their deformation is
acceptable.
