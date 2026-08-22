# Rig QA previews

Rendered checks belong here and are not loaded by production scenes.

Every approved source or mesh stage must include:

- transparent/checkerboard overview;
- dark-background alpha check;
- magenta-background alpha check;
- labelled deformation comparison when bones and weights are introduced.

Passing a structural validator does not replace visual review.

The active Task 4B previews are intentionally absent after the joint-weight
correction. They must be regenerated with a GL/Xvfb Godot run before review.
The old, rejected renders live under `rejected_task4b_old_weights/` and are not
evidence for the current scene.
