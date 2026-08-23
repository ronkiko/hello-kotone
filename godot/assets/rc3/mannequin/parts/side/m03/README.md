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

Each leg is one complete rigid hip-to-foot part. The torso keeps the complete
pelvis and stable buttock silhouette. A rounded proximal overlap at the top of
each leg sits behind that shell and is centred on the internal femoral-head
position. The visible lower edge of the torso is higher at the front and curves
down under the buttock; it is not the rotation axis.

`preview/neutral_assembly.png` is only a visual assembly check. It is not a
runtime texture and its placement is not an approved rest pose.

## Current gate

Status: `six_part_assets_approved_ready_for_skeleton`.

The operator accepted the six-part asset construction after reviewing:

- head-to-body scale;
- shoulder and neck joins;
- diagonal hip seam, hip-cap overlap and buttock silhouette;
- both complete hands and feet;
- consistent left-facing direction;
- absence of background pixels or cropped silhouettes.

The next gate creates the six-bone hierarchy step by step in the Godot editor.
Asset placement in the preview must not be copied as unverified bone
coordinates; every pivot is measured and inspected with the operator.
