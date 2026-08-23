# KTN-RC3-M03 clean rebuild

M03 is rebuilt as an independent six-part rigid Kotone model. The robot and
M02 do not define its proportions, skeleton or artwork.

The local `assets/` directory contains the six operator-approved textures
required for Godot import. There is intentionally no scene, script, skeleton,
rig or animation at this gate.

`torso.png` retains the complete pelvis and stable buttock silhouette. Both
rigid leg textures contain a hidden rounded proximal overlap centred on the
internal femoral-head position. The overlap sits behind the torso shell and
prevents gaps when a complete rigid leg rotates at the hip.

## Step 1/6: Torso

The first isolated rig gate contains exactly one root bone: `Torso`. Its pivot
is registered at `(110, 350)` inside `torso.png`, near the pelvis centre.
`Torso` stays at scene `(0, 0)`. The visible torso is a four-vertex `Polygon2D`
inside the sibling `Polygons` node, bound to `Skeleton2D` and fully weighted to
`Torso`, matching the rendering pattern of the upstream robot. Its vertices
place source pixel `(110, 350)` on the root. The torso root keeps an identity
transform and uses the explicit measured pelvis-to-neck axis.

Open `res://player/kotone_bot_m03/torso_rig.tscn` in the Godot editor and select
`M03TorsoRig/Skeleton2D/Torso`. Do not add or move nodes yet. The operator first
checks the pivot, axis and sprite registration described below.

Run `./m03-torso-preview.sh` for the isolated runtime check. It starts at rest;
press `Q` for -10 degrees, `R` to reset, and `E` for +10 degrees. Only the torso
may rotate. There is intentionally no head, arm, leg, animation or game player.

Expected editor state:

- the scene tree has `M03TorsoRig -> Skeleton2D -> Torso`, plus
  `M03TorsoRig -> Polygons -> Torso`;
- the bone origin is inside the pelvis, not on the lower skin edge;
- the bone axis points upward through the torso and ends near the shoulder;
- the torso Polygon2D has `Skeleton = ../../Skeleton2D` and all four vertices
  weighted to `Torso`;
- the Inspector shows automatic length/angle calculation disabled;
- no other `Bone2D` node exists at this gate.

## Step 2/6: Head

`Head` is the only new bone. It is a child of `Torso` and its root is placed
directly at the measured neck joint: Torso-local `(16, -328)`. `Torso` has the
matching explicit pelvis-to-neck axis. The head sprite's internal neck point
`(80, 190)` is registered to that root. The visible head is a four-vertex
Polygon2D, weighted 100% to `Torso/Head`; it follows the skeleton just as the
robot head does. The model has no facial, jaw, hair, or deformation bones.

In the editor, select `Skeleton2D/Torso/Head` and check:

- its origin is at the neck, not at the centre of the head;
- the bone axis rises through the head;
- the `Polygons/Head` node resolves `Skeleton` to `Skeleton2D` and contains
  only the `Torso/Head` weight;
- rotating `Head` moves the whole head around the neck while the torso stays
  fixed.

Do not add arms or legs yet. After acceptance, the next separate change adds
only the far arm.
