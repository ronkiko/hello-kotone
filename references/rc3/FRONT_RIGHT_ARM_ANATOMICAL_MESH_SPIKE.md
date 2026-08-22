# Task 4I: anatomical-right elbow topology

## Goal

Build the first production-candidate human elbow topology from the architecture
in `FRONT_JOINT_RIGGING_ARCHITECTURE.md`. This replaces Task 4H's dense
diagnostic strip; it does not compare against or display the rejected rigid
cutout.

The mesh has 24 semantic vertices, 18 cells and two internal joint points.
Upper arm, forearm and hand regions are rigidly weighted. Only the transverse
elbow and wrist rings share adjacent bones at `50/50`.

## Static verification

From the repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 \
  python3 godot/scripts/mannequin/validate_front_right_arm_anatomical_mesh_spike.py
```

## Godot 4.7.2 runtime verification

From `godot/`:

```bash
godot --headless --path . --editor --quit
godot --headless --path . \
  --script res://scripts/mannequin/validate_front_right_arm_anatomical_mesh_spike.gd
xvfb-run -a godot --path . \
  --script res://scripts/mannequin/render_front_right_arm_anatomical_mesh_spike.gd
```

Expected terminator:

```text
FRONT RIGHT ARM ANATOMICAL MESH SPIKE GODOT VALIDATION PASSED
```

The renderer creates light, dark and magenta sheets containing the new arm at
`0°`, `30°`, `60°` and `90°` of anatomically valid downward elbow flexion.
Every pose is rasterized in its own `500x820` `SubViewport`; only completed
panel images are stitched into the final `2000x820` sheet. This prevents a
full mannequin instance from crossing a panel boundary and covering a
neighbouring pose.

The panel is an arm-only close-up, not a crop of the full mannequin. All
`Sprite2D` visuals below `BaseRig` are hidden while `Skeleton2D` and its bones
remain active. The anatomical-right elbow at source coordinate `(414, 263)` is
anchored at panel coordinate `(286, 270)`. This leaves room for the straight
arm toward viewer-left and for downward flexion through 90 degrees.

The first runtime sheets produced before this isolation fix are invalid QA
evidence: their four full mannequin instances shared one wide viewport and
overlapped. They must be overwritten by a new GL/Xvfb render before judging
the elbow at any angle.

The second runtime sheets produced after panel isolation but before the
arm-only close-up are also invalid QA evidence: they still framed a partial
full mannequin rather than guaranteeing visibility of the target mesh.

Review the elbow for pinching, loss of thickness, broken contour, holes,
doubled pixels and texture folding. Do not tune weights or add a patch during
the runtime pass. If the local topology fails, record which angle first fails;
the next decision is an artwork/volume correction, not a wider weight gradient.
