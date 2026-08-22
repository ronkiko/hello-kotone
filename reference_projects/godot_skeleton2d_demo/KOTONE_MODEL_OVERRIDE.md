# Kotone-bot model override

This official Skeleton2D demo is the temporary playable training field for
`KTN-RC3-M01`.

- Active player: `res://player/kotone_bot_m01/player.tscn`
- Preserved original: `res://player/player.tscn`
- Selection point: external resource id `4` in `level.tscn`
- Launcher: `./demobot.sh`

The original gBot scene, art, controller and launcher are unchanged and remain
the construction reference. To restore gBot, change only resource id `4` in
`level.tscn` back to `res://player/player.tscn`.

Kotone-bot reuses the demonstrated Skeleton2D/Polygon2D assembly technique but
does not copy the robot's gait. Its procedural poses target human weight shift
and arm counter-swing. This M01 mannequin is an integration baseline; improved
elbows and knees are reserved for M02.
