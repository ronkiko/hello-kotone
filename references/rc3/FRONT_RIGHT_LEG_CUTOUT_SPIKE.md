# Task 4E: front right leg cutout spike

## Scope

This spike validates the approved pelvis, anatomical-right thigh, calf and foot
as a rigid cutout chain. It is not a walk cycle and it does not attempt to
represent knee flexion into camera depth.

The only tested motion is a small `-4..+4` degree hip
abduction/adduction range with the knee and ankle held neutral. This is a real
front-plane hip motion and is sufficient to expose missing hip, knee or ankle
overlap art.

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
must overwrite the same three preview files before runtime approval; it proves
that the committed scene, Bone2D hierarchy and sprite transforms—not a separate
mock-up—produce the poses. The Godot validator and renderer remain mandatory on
a workstation with Godot 4.7.2 before this stage can be approved.
