# Front leg mesh spike: implementation note

This note is the handoff for `kotone_front_leg_mesh_spike.tscn`. It describes
the actual coordinate system and the weight rule; no visual guesswork is needed.

## What was wrong

The first spike spread every bone across most of the leg. Its strongest
`knee_right` influence was around source Y=925 although the knee pivot is at
Y=765. Its strongest `ankle_right` influence was around Y=1150 although the
ankle pivot is at Y=1040. Rotating the knee therefore bent the whole limb like
a rubber hose instead of keeping the thigh and calf approximately rigid.

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

Visual acceptance at 0, 20 and 45 degrees:

- the thigh above the knee stays still when only `knee_right` rotates;
- the calf is nearly rigid and rotates around `(555, 765)`;
- deformation is confined to a narrow band around the kneecap;
- no banana curve, local narrowing, transparent tear or duplicated edge;
- tights and shoe texture remain continuous;
- dark and magenta previews have no halo.

The previous Task 4B PNGs were moved under
`preview/rejected_task4b_old_weights/`; they are historical evidence only and
must not be used to approve the corrected scene.
