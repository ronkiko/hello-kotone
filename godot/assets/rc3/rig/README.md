# Kotone RC3 deformable rig

This is the only active artwork root for the RC3 character rig.

## Direction and rest pose

- Initial view: front.
- Rest pose: front-facing T-pose.
- Anatomical left/right are always named from Kotone's point of view. In the
  front view, Kotone's right side appears on the viewer's left.
- Side and back views are future, separate artwork/rig tasks. Do not derive them
  by rotating the front artwork.

## Production technique

- `Skeleton2D` and `Bone2D` provide the hierarchy.
- Character regions are textured `Polygon2D` meshes with bone weights.
- Limbs must deform at joints; they must not be reconstructed as the archived
  chain of rigid PNG segments.
- Face variants, front hair and the badge may remain separate layers when that
  is useful for expression or secondary motion.

## Directory contract

- `source/` contains approved full-resolution authoring artwork.
- `mesh/` contains textures/masks prepared from an approved source for Godot.
- `preview/` contains rendered visual QA, never production input.
- `rig_manifest.json` records the active approach and stage gate.
- Active scenes belong in `res://scenes/rig/`.
- Active tooling belongs in `res://scripts/rig/`.

The previous 29-part side-view experiment is preserved under
`res://archive/rc3_rigid_cutout/` and must not be referenced by active scenes.

## Current stage gate

The next deliverable is an approved `source/kotone_front_t_pose.png`. No mesh,
full rig or animation may be accepted before that source passes visual and
alpha QA.
