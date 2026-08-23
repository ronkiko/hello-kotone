# Human Skeleton2D reference

Reference-only copy of **Human Skeleton 2D 1.1.3** by René van der Ark.

- Godot Asset Library: https://godotengine.org/asset-library/asset/5270
- Upstream repository: https://codeberg.org/renevanderark/skeleleton-2d-asset
- Upstream commit: `acad03b851e65307f16bfd2a517c1236a4dc20c4`
- Downloaded archive SHA-256: `63640fa5a6e803959dcc3926322074be553b3ce21f30ceff86e3cc1b525d441e`
- Declared engine version: Godot 4.6
- License: GPLv3; see `LICENSE.txt`

This directory is not part of the Hello Kotone runtime. It is retained as a
rigging reference and its art must not be copied into the game model.

## What M02 copies from the rig

The useful part is the transform contract, not the sample proportions:

1. `UpperArm` starts at the measured shoulder joint.
2. `LowerArm` is a child whose local position is the measured
   shoulder-to-elbow vector.
3. `Hand` is a child whose local position is the measured elbow-to-wrist
   vector.
4. Each visual part is registered so its local origin is exactly its proximal
   joint. Rotating the bone therefore cannot detach the artwork from the
   parent joint.
5. Bone `rest` transforms record the neutral pose. Animation changes local
   rotation relative to that rest pose; it does not compensate for incorrectly
   cropped or scaled art.

The current M02 side prototype follows this three-link transform contract and
keeps the reference outside runtime. M03 is reserved for a clean rebuild and
may reuse the transform method, but must not copy M02 artwork or generated
cutouts.
