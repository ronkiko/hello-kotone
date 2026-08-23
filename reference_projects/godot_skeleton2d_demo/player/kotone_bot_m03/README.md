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

The next step creates one root `Torso` bone and five direct child bones:
`Head`, `ArmFar`, `ArmNear`, `LegFar` and `LegNear`. Every pivot will be added
and inspected separately in the Godot editor with the operator.
