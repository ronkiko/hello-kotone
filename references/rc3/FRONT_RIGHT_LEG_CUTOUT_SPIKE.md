# Task 4E: front right leg cutout spike

## Scope

This spike validates the approved pelvis, anatomical-right thigh, calf and foot
as a rigid cutout chain. It is not a walk cycle and it does not attempt to
represent knee flexion into camera depth.

The only tested motion is a small `-4..+4` degree hip
abduction/adduction range with the knee and ankle held neutral. This is a real
front-plane hip motion and is sufficient to expose missing hip, knee or ankle
overlap art.

Godot uses screen coordinates with positive Y downward. For the anatomical
right leg shown on the viewer's left, `+4` degrees moves the ankle toward
viewer-left and is abduction; `-4` degrees moves it toward the body center and
is adduction. The runtime validator checks this spatial result, not only the
numeric angle.

## Scene contract

- chain: `pelvis -> hip_right -> knee_right -> ankle_right`;
- global pivots: pelvis `(627,545)`, hip `(555,565)`, knee `(555,765)`, ankle
  `(555,1040)`;
- four approved Sprite2D textures, with their manifest top-left offsets;
- pelvis draws over thigh, thigh over calf, calf over foot;
- no Polygon2D, weight painting, scale proxy or knee rotation;
- no AnimationPlayer or full-body rig yet.

## Verification

From `godot/`:

```bash
python3 scripts/mannequin/validate_front_right_leg_cutout_spike.py
python3 scripts/mannequin/render_front_right_leg_cutout_spike.py
godot --headless --path . --editor --quit
godot --headless --path . --script res://scripts/mannequin/validate_front_right_leg_cutout_spike.gd
xvfb-run -a godot --path . --script res://scripts/mannequin/render_front_right_leg_cutout_spike.gd
```

The Pillow renders are deterministic preflight evidence. The Godot command
overwrites the same three preview files and proves that the committed scene,
Bone2D hierarchy and sprite transforms—not a separate mock-up—produce the
poses.

## Runtime result

Runtime QA passed with `Godot 4.7.2.stable.official` and was recorded in commit
`87a291ff107d9279334069ba57165d0df92bced3`:

- editor import completed successfully;
- the Godot validator printed
  `FRONT RIGHT LEG CUTOUT SPIKE GODOT VALIDATION PASSED`;
- the GL/Xvfb renderer wrote all three `1500x900` previews;
- light, dark and magenta previews show no joint gaps;
- hip direction is correct, knee and ankle stay neutral, and scale is unchanged.

The unsupported V-Sync warning from the headless/X11 driver is non-blocking.
The initial runtime run proved the mechanics but its abduction/adduction labels
were reversed. That evidence is retained for diagnosis but does not approve the
direction labels. The corrected renderer and spatial validator must be rerun
before Task 4E direction semantics are approved. Full neutral mannequin
assembly remains independently approved by Task 4F; walk animation, weight
painting and clothing remain outside this gate.
