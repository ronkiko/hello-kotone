# RC3 Kotone mannequin pipeline

## Decision

RC3 locomotion is built on a neutral articulated mannequin whose proportions
belong to Kotone. It is not a generic doll and it is not a one-piece deforming
sprite. Clothing, hair and accessories are introduced only after the mannequin
can hold weight and walk convincingly.

The Task 4B front-leg depth proxy remains historical rigging research. Vertical
`scale.y = cos(angle)` proved that localized weights work, but it produced a
telescoping leg and is rejected as the front-walk solution.

## Canonical front proportions

The clothed reference remains
`godot/assets/rc3/rig/source/kotone_front_t_pose.png`. The mannequin source is
`godot/assets/rc3/mannequin/source/kotone_front_mannequin_t_pose.png`.

Both sources use a 1254 x 1254 canvas and the same registration:

- clothed reference alpha bounds: 827 x 1106 at (213, 54);
- mannequin alpha bounds: 829 x 1111 at (213, 54);
- the 2 px width and 5 px height delta comes from replacing heels and clothing
  with neutral feet and the body silhouette;
- head, shoulder line, pelvis, knees and overall scale must not be repositioned
  during part extraction.

The mannequin intentionally preserves Kotone's head, bust, waist, pelvis and
limb proportions. Its light warm skin tone is only a neutral technical surface;
it has no intimate anatomical detail.

## Stage gates

1. `front_mannequin_source_approved`
2. `front_mannequin_parts_approved`
3. `single_leg_cutout_motion_approved`
4. `front_mannequin_neutral_rig_approved`
5. `front_mannequin_walk_approved`
6. `clothing_layers_allowed`

Do not skip a gate. In particular, do not create bones, weights or animation
from the current one-piece source before its proportions are approved.

## Rig-ready part contract

After source approval the figure is redrawn/extracted as separate transparent
parts, not merely cropped along visible seams:

- pelvis/root;
- torso and chest;
- neck and head;
- left/right upper arm, forearm and hand;
- left/right thigh, calf and foot.

Every rotating joint must contain hidden overlap art under its neighbour. No
joint may expose transparent gaps at its tested range. Parts use anatomical
left/right naming.

The first motion proof uses one leg only. It must demonstrate contact, down,
passing and up poses without sideways knee rotation or uniform telescoping.
Front-view depth may use alternate/cel thigh, calf or foot art in addition to
small mesh corrections. Side-view legs may later use ordinary two-bone planar
rotation.

## Clothing order

Only after the mannequin walk is approved:

1. tights and shoes;
2. shirt, vest and sleeves;
3. skirt panels attached to the pelvis;
4. head/face and hair layers;
5. lanyard and badge;
6. secondary cloth and hair motion.

All wearable parts inherit the approved mannequin pivots and rest coordinates.

