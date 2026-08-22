# Task 4G: controlled front articulation spike

## Goal

Prove that the complete Task 4F mannequin can move selected joints in the image
plane without gaps, reversed directions or telescoping. This is a pose sheet,
not an animation and not a walk cycle.

## Approved poses

1. neutral T-pose;
2. both straight arms lowered 12 degrees at the shoulders;
3. both forearms lowered 18 degrees at the elbows;
4. both straight legs abducted 4 degrees at the hips.

Screen-space signs are deliberate:

- anatomical-right shoulder and elbow use negative angles to move down;
- anatomical-left shoulder and elbow use positive angles to move down;
- anatomical-right hip uses `+4°` to move toward viewer-left;
- anatomical-left hip uses `-4°` to move toward viewer-right.

Both knees and both ankles remain at zero rotation and unit scale in every pose.
No `AnimationPlayer`, IK, `Polygon2D`, weight painting or clothing is introduced.

## Static verification

From the repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 \
  python3 godot/scripts/mannequin/validate_front_articulation_spike.py
```

## Required Godot runtime verification

From `godot/` on the Godot 4.7.2 workstation:

```bash
godot --headless --path . --editor --quit
godot --headless --path . \
  --script res://scripts/mannequin/validate_front_articulation_spike.gd
xvfb-run -a godot --path . \
  --script res://scripts/mannequin/render_front_articulation_spike.gd
```

Expected validator terminator:

```text
FRONT ARTICULATION SPIKE GODOT VALIDATION PASSED
```

The validator must explicitly pass both arm-down directions, both hip-abduction
directions, and the locked knee/ankle rotation and scale checks. The renderer
must create three `2000x900` sheets in `assets/rc3/mannequin/preview/`.

Review all panels for shoulder, elbow and hip gaps; doubled edges; incorrect
front/back layering; missing hands or feet; and any apparent knee bending. Stop
after recording the runtime evidence. Do not create a walk cycle.

## Runtime result and visual decision

Godot 4.7.2 completed the editor scan, validator and renderer successfully. The
runtime evidence was recorded in commit `00b39c4`. That proves bone directions,
locked knee/ankle transforms and pose generation, but it does **not** approve
the cutout technique for animation.

Visual review of the three committed sheets produced this decision:

- neutral T-pose: accepted as the registration reference;
- shoulders down 12 degrees: direction is correct, but the rigid shoulder
  transition is visible and is not final-quality deformation;
- elbows down 18 degrees: rejected; the rectangular proximal ends of both
  forearm PNG cutouts protrude as corrupted blocks;
- hips abducted 4 degrees: direction is correct, but the rigid hip transition
  remains slightly visible and is not final-quality deformation.

The elbow failure is not an angle-sign error and must not be hidden by reducing
the test angle. A child `Sprite2D` rotates as a rigid rectangle; once its overlap
with the upper-arm sprite opens, pixels intended to remain covered become
visible. The next gate is therefore a single anatomical-right arm spike using
one continuous `Polygon2D` mesh weighted across upper-arm, forearm and hand
bones. The accepted neutral rig remains unchanged. Full-rig conversion, walk
animation and clothing remain prohibited until that narrow spike is reviewed.
