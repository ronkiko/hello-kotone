# Rig QA previews

Rendered checks belong here and are not loaded by production scenes.

Every approved source or mesh stage must include:

- transparent/checkerboard overview;
- dark-background alpha check;
- magenta-background alpha check;
- labelled deformation comparison when bones and weights are introduced.

Passing a structural validator does not replace visual review.

The active Task 4B previews document the final depth-proxy experiment. The
experiment passed its structural checks but was rejected as a locomotion
solution because the calf telescopes vertically instead of producing a
convincing front-view step.

Older rejected renders live under `rejected_task4b_old_weights/` and
`rejected_task4b_sideways_rotation/`; they are historical evidence only.
