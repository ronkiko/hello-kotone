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
is registered at `(110, 350)` inside `torso.png`, near the pelvis centre. The
`Torso` node itself has this exact position, rather than world origin. Its
300 px local axis is rotated exactly -90 degrees, so the visible bone points
upward through the waist and chest. The torso
sprite is the only art node and is a direct child of this bone.

Open `res://player/kotone_bot_m03/torso_rig.tscn` in the Godot editor and select
`M03TorsoRig/Skeleton2D/Torso`. Do not add or move nodes yet. The operator first
checks the pivot, axis and sprite registration described below.

Run `./m03-torso-preview.sh` for the isolated runtime check. It starts at rest;
press `Q` for -10 degrees, `R` to reset, and `E` for +10 degrees. Only the torso
may rotate. There is intentionally no head, arm, leg, animation or game player.

Expected editor state:

- the scene tree has `M03TorsoRig -> Skeleton2D -> Torso -> Art_torso`;
- the bone origin is inside the pelvis, not on the lower skin edge;
- the bone axis points upward through the torso and ends near the shoulder;
- `Art_torso` preserves the upright source image at rest; its local offset and
  counter-rotation only compensate for the bone's -90 degree rest axis;
- the Inspector shows explicit length/angle calculation disabled;
- no other `Bone2D` node exists at this gate.

After operator acceptance, the next separate change adds only the `Head` bone.
