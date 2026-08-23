# KTN-RC3-M03 six-part asset gate

M03 is a new minimal rigid side model. It does not inherit M02 textures, bone
coordinates, scene files or animation.

This gate contains exactly six candidate RGBA body assets:

1. `torso.png`;
2. `head.png`;
3. `arm_far.png`;
4. `arm_near.png`;
5. `leg_far.png`;
6. `leg_near.png`.

All components face screen-left. The complete future model may be mirrored as
one unit to face screen-right. Individual body parts must never be mirrored in
different directions.

The six parts are intended for a six-bone rigid cutout. Arms do not bend at
the elbows or wrists, legs do not bend at the knees or ankles, and this model
does not use `Polygon2D` deformation, vertex weights or IK.

`preview/neutral_assembly.png` is only a visual assembly check. It is not a
runtime texture and its placement is not an approved rest pose.

## Current gate

Status: `six_part_assets_draft_operator_review_required`.

Before any `Skeleton2D` or `Bone2D` node is created, the operator reviews:

- head-to-body scale;
- shoulder and neck joins;
- hip overlap;
- both complete hands and feet;
- consistent left-facing direction;
- absence of background pixels or cropped silhouettes.

No skeleton work may begin until this asset gate is explicitly accepted.
