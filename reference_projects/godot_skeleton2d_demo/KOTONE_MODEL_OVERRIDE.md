# Kotone-bot model override

This official Skeleton2D demo is the temporary playable training field for
`KTN-RC3-M01`.

- Active player: `res://player/kotone_bot_m01/player.tscn`
- Disabled experiment: `res://player/kotone_bot_m02/player.tscn`
- Preserved original: `res://player/player.tscn`
- Selection point: external resource id `4` in `level.tscn`
- Launcher: `./demobot.sh`
- Isolated M02 visibility gate: `./m02-neutral-preview.sh`

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
