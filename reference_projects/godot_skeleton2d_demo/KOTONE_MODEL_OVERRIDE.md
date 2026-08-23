# Kotone-bot model override

This official Skeleton2D demo is the temporary playable training field for
`KTN-RC3-M01`.

- Active player: `res://player/kotone_bot_m01/player.tscn`
- Disabled experiment: `res://player/kotone_bot_m02/player.tscn`
- Preserved original: `res://player/player.tscn`
- Selection point: external resource id `4` in `level.tscn`
- Launcher: `./demobot.sh`
- Isolated M02 visibility gate: `./m02-neutral-preview.sh`
- Isolated animated M03 side gate: `./m03-side-preview.sh`

The original gBot scene, art, controller and launcher are unchanged and remain
the construction reference. To restore gBot, change only resource id `4` in
`level.tscn` back to `res://player/player.tscn`.

Kotone-bot reuses the demonstrated Skeleton2D/Polygon2D assembly technique but
does not copy the robot's gait. Its procedural poses target human weight shift
and arm counter-swing. This M01 mannequin is an integration baseline; improved
elbows and knees are reserved for M02.

The M01 live articulation gate intentionally used clearly visible rigid
whole-limb motion: shoulders and hips move while elbows, wrists, knees and
ankles remain locked. This distinguishes a working bone/mesh binding from a
subtle or malformed final gait. It is a diagnostic motion proof, not the final
walk animation.

The active M01 keeps its original 0.04 world-relative scale and 22x44
floor-aligned collision. Its camera zoom is 6 instead of 4, so the model,
platforms and environment are presented 150% larger without changing their
physical proportions.

`KTN-RC3-M02` is the next mechanical approximation. It reconstructs the same
approved silhouette from 15 independently pivoted rigid parts and adds visible
two-layer joint caps. Its gait has explicit contact, mid-stance, toe-off and
bent-knee swing phases. Its first live launch rendered only the joint caps; the
15 art sprites were invisible. M02 is therefore disabled and must remain an
isolated diagnostic scene until a Godot render visibly proves every segment.
M01 and gBot remain available; only resource id `4` selects the active model.

The first M02 recovery gate deliberately contains no controller, collision,
camera, animation or joint caps. `neutral_rig.tscn` is generated directly from
the previously rendered Task 4F neutral scene, with only standalone-demo
texture paths and the root name changed. Run `./m02-neutral-preview.sh` and
accept the gate only if the complete neutral mannequin is visible. Do not
change `level.tscn` during this test.

The operator visually confirmed the complete M02 neutral render on 2026-08-23.
M02 remains front-facing, so it is retained as a registration and comparison
model rather than promoted as the side-scroller player.

`KTN-RC3-M03` is the first true side-facing mechanical gate. It uses the only
available coherent side turnaround, cleaned to a right-facing 1254 x 1254
registration source without a baked-in arm, one separately generated arm split
at its measured elbow and wrist and instantiated for both near and far layers,
and one three-piece side leg instantiated for both near and far layers. Run `./m03-side-preview.sh`; it
animates both legs and both arms in place without changing `level.tscn` or the
active M01 rollback player. The
launcher performs a headless import pass first, so a fresh checkout has valid
Texture2D resources before the preview scene is parsed.

For the next arm-rig revision, use
`../human_skeleton2d_reference/human_skeleton_2d.tscn` as the hierarchy and
joint-registration reference. M03 now follows its three-link arm hierarchy
(`UpperArm -> LowerArm -> Hand`) with sprite origins registered to the measured
shoulder, elbow, and wrist. The reference is GPLv3 and remains outside the
runtime.

The M03 motion gate uses a two-link analytic leg solver with the measured
200 px hip-to-knee and 285 px knee-to-ankle lengths. Idle keeps the two ankle
targets subtly staggered instead of stacking every cutout exactly. Walk uses
six keys per cycle (contact, loading, midstance, heel lift, toe-off, swing),
with the far leg offset by half a cycle and a restrained opposing arm swing.
The preview alternates three seconds of idle with six seconds of walk; press
`1` for a fixed idle, `2` for a fixed walk, or `0` to restore automatic mode.
The limb textures use rounded alpha caps centred on every measured joint; the
long source overlaps are not allowed to protrude when a knee, ankle, elbow, or
wrist rotates. In idle the near and far arms share one side-profile pose so the
duplicated cutouts resolve to one clean silhouette instead of doubled hands.
The leg pivots follow the measured centreline of the source silhouette at
hip `(619, 575)`, knee `(609, 775)`, and ankle `(593, 1060)`. The IK solver
compensates for both non-vertical rest vectors. The duplicated far-arm artwork
is temporarily hidden because its hand reads as an unrelated foot behind the
pelvis; its bone chain remains available for a later distinct far-arm source.
