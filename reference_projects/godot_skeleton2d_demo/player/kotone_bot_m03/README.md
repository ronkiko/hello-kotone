# KTN-RC3-M03 clean rebuild

M03 is rebuilt as an independent six-part rigid Kotone model. The robot and
M02 do not define its proportions, skeleton or artwork.

The local `assets/` directory contains the six candidate textures required for
Godot import and operator inspection. There is intentionally no scene, script,
skeleton, rig or animation at this gate.

Both rigid leg textures start at the diagonal hip seam and include the
hip/buttock cap. The matching lower-pelvis alpha was removed from `torso.png`;
this prevents a duplicated rear silhouette and gives each future leg a broad,
readable rotation attachment instead of a thin vertical insertion.

The next step begins only after the operator accepts the six assets. It will
create one root `Torso` bone and five direct child bones: `Head`, `ArmFar`,
`ArmNear`, `LegFar` and `LegNear`.
