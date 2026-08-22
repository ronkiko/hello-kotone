# RC3 rigid-cutout archive

This directory preserves the abandoned Task 3/Task 4 experiment based on 29
independent PNG parts attached to `Sprite2D`/`Bone2D` nodes.

The experiment was archived after commit `90de71c` because independently
generated limb segments could not form continuous shoulders, elbows, knees or
ankles. Repositioning rigid sprites could not restore the missing overlap art.

Nothing in this directory is a production input. The scene and scripts use
`.disabled` suffixes so Godot does not import or execute them. They are retained
only for visual comparison and historical reference.

The active RC3 rig starts in `res://assets/rc3/rig/` from a front-facing T-pose
and uses deformable `Polygon2D` meshes with `Skeleton2D`.
