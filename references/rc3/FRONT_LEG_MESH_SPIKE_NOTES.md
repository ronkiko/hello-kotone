# Front leg mesh spike: implementation note

> Historical Task 4B research only. The localized weights passed validation,
> but the depth proxy was rejected for locomotion because it visually
> telescopes the calf. RC3 continues with the proportional mannequin pipeline
> documented in `RC3_MANNEQUIN_PIPELINE.md`.

This note is the handoff for `kotone_front_leg_mesh_spike.tscn`. It describes
the actual coordinate system and the weight rule; no visual guesswork is needed.

## What was wrong

The first spike spread every bone across most of the leg. Its strongest
`knee_right` influence was around source Y=925 although the knee pivot is at
Y=765. Its strongest `ankle_right` influence was around Y=1150 although the
ankle pivot is at Y=1040. The original QA then compounded the problem by
rotating the calf in the image plane, which is not an anatomically valid knee
bend in a front view.

## Fixed rest coordinates

All values are pixels in the 1254x1254 T-pose source:

- anatomical right hip: `(555, 560)`;
- anatomical right knee: `(555, 765)`;
- anatomical right ankle: `(555, 1040)`;
- chain: `pelvis -> hip_right -> knee_right -> ankle_right`;
- working mesh: `FrontLegMesh`, 72 vertices, 48 cells.

## Weight rule already written into the scene

Weights depend on each vertex's source Y coordinate. Only 60-pixel bands
around real joints are blended:

```text
y <= 735       hip=1
735 < y < 795  hip=(795-y)/60, knee=(y-735)/60
795 <= y <=1010 knee=1
1010 < y <1070 knee=(1070-y)/60, ankle=(y-1010)/60
y >= 1070      ankle=1
```

This makes the hip/knee crossover exactly Y=765 and the knee/ankle crossover
exactly Y=1040. Never replace this with a smooth gradient over the full leg.

## Required Godot verification

### Anatomical rule for the front view

Do not rotate `knee_right` left or right in the image plane. A human knee flexes
backward in the sagittal plane; from the front this is motion into depth, not a
45-degree sideways hinge. Changing the rotation sign only changes one invalid
sideways bend into the opposite invalid sideways bend.

The renderer therefore uses an orthographic depth proxy:

- poses are `0`, `25` and `40` degrees of out-of-plane flexion;
- calf projected length is `cos(angle)` through `knee.scale.y`;
- `ankle.scale.y` uses the reciprocal value so the shoe keeps its shape;
- no bone receives an in-plane rotation;
- the foot rises vertically as the projected calf shortens.

This spike checks mesh continuity and depth foreshortening. It is not a complete
front walk pose: final animation will additionally require overlap, draw order
and subtle hip motion. A literal side-view knee arc requires a separate side
source and side rig.

Run from the `godot/` directory with Godot 4.7.2:

```bash
python3 scripts/rig/validate_front_leg_mesh_spike_static.py
godot --headless --path . --editor --quit
godot --headless --path . --script res://scripts/rig/validate_front_leg_mesh_spike.gd
xvfb-run -a godot --path . --script res://scripts/rig/render_front_leg_mesh_spike.gd
```

The last command must create all three active `task4b_leg_mesh_spike*.png`
files and exit zero. Dummy headless rendering now exits nonzero instead of
claiming success without rasterizing.

Visual acceptance at `0`, `25` and `40` degrees of depth flexion:

- the thigh above the knee stays still;
- the calf shortens vertically without moving left or right;
- the foot rises but does not become vertically squashed;
- deformation is confined to a narrow band around the kneecap;
- no sideways dislocation, banana curve, transparent tear or duplicated edge;
- tights and shoe texture remain continuous;
- dark and magenta previews have no halo.

The previous Task 4B PNGs were moved under
`preview/rejected_task4b_old_weights/`; they are historical evidence only and
must not be used to approve the corrected scene.
