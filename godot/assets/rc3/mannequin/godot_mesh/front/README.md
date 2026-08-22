# Editor-authored full front mannequin

This directory is the clean destination for the gBot-method RC3 mannequin.
The current contents are a contract, not finished art or a finished rig.

`KTN-RC3-M01` required atlas islands:

- `body`
- `head`
- `arm_right`
- `arm_left`
- `leg_right`
- `leg_left`

Each arm is one continuous shoulder-to-hand island and each leg is one
continuous hip-to-foot island. Do not copy the rejected Task 4I/4J arm mesh or
reassemble the old 15 rectangular cutouts as the production rig.

The six M01 source islands are built deterministically from the approved
registration parts. `KTN-RC3-M02` will later replace their joint art/topology
with anatomically refined versions after whole-body locomotion is proven.

Create polygon points, cells, bone synchronization and weights in the Godot
4.7.2 editor. The complete contract and gate order are in
`references/rc3/FULL_HUMANOID_REFERENCE_BLUEPRINT.md`.
