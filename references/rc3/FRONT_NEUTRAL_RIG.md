# Task 4F: full front neutral mannequin rig

## Goal

Assemble all 15 approved front mannequin parts into one neutral `Skeleton2D`
scene. The neutral scene must reproduce the approved T-pose before any walk,
clothing or mesh deformation is attempted.

## Contract

- exactly 15 `Bone2D` nodes and 15 `Sprite2D` nodes;
- anatomical left/right naming from the character's point of view;
- bone pivots and sprite registration come from
  `parts/front/front_parts_manifest.json`;
- hierarchy:
  - pelvis -> torso -> head/neck;
  - torso -> right arm -> right forearm -> right hand;
  - torso -> left arm -> left forearm -> left hand;
  - pelvis -> right hip -> right knee -> right ankle;
  - pelvis -> left hip -> left knee -> left ankle;
- neutral rotations and unit scales everywhere;
- approved back-to-front layer order is preserved;
- no `Polygon2D`, weights, `AnimationPlayer`, IK or clothing.

Task 4F validates registration and hierarchy only. It does not prove that a
front-view knee can be animated by rotating it in the image plane.

## Static verification

From the repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 \
  python3 godot/scripts/mannequin/validate_front_neutral_rig.py
```

## Required Godot runtime verification

From `godot/` on the Godot 4.7.2 workstation:

```bash
godot --headless --path . --editor --quit
godot --headless --path . \
  --script res://scripts/mannequin/validate_front_neutral_rig.gd
xvfb-run -a godot --path . \
  --script res://scripts/mannequin/render_front_neutral_rig.gd
```

Expected validator terminator:

```text
FRONT NEUTRAL RIG GODOT VALIDATION PASSED
```

The renderer must produce three `1500x900` source-versus-rig comparisons in
`assets/rc3/mannequin/preview/`. Review all three backgrounds for registration,
layering, joint gaps, halos and missing parts. Leave generated `.uid`, `.import`
and preview files available for architectural review; do not begin animation.

## Runtime result

Task 4F passed on `Godot 4.7.2.stable.official` and was recorded in commit
`1a2258e4c19dda9d9aede8c9e9b24bbd7d6ae756`.

- editor scan, validator and GL/Xvfb renderer completed successfully;
- the validator printed `FRONT NEUTRAL RIG GODOT VALIDATION PASSED`;
- all 15 bones, pivots, neutral rotations, unit scales, texture registrations
  and layer indices passed;
- all three `1500x900` comparisons contain the complete mannequin with no joint
  gaps or missing parts;
- the only warnings concern terminal bones and unavailable headless V-Sync.

Task 4F is approved. Controlled articulation testing may begin, but walk
animation, weight painting and clothing are still prohibited.
