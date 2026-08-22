# RC3 full humanoid reference blueprint

## Decision and technical model numbers

The official Godot 4.7 Skeleton2D demo is the construction reference for the
complete RC3 front mannequin, not a source of robot artwork. Kotone must use
her own silhouette, proportions and texture, while matching the demo's proven
division into a small number of continuous weighted regions.

Task 4J proved the correct `Polygon2D` to `Skeleton2D` binding contract. Its
hand-authored Kotone arm topology is visually rejected and must not be copied
into the full mannequin.

- `KTN-RC3-M01` is the first complete technical mannequin. It keeps Kotone's
  approved proportions and neutral surface but deliberately targets the demo's
  forgiving whole-region construction. Its purpose is assembly and locomotion.
- `KTN-RC3-M02` is the later anatomical refinement. Elbows, knees, shoulders,
  hips, wrists and ankles are redrawn or retopologized only after M01 can idle,
  walk, run and jump as a coherent body.

These numbers identify rig mannequins, not new canon character designs.

## What the official character actually contains

The runtime character uses one `Skeleton2D`, 16 `Bone2D` nodes and seven
`Polygon2D` nodes drawn from one transparent atlas.

| Polygon2D | Complete visual region | Active bone chain | Vertices | Explicit cells |
| --- | --- | --- | ---: | ---: |
| `RightArm` | shoulder through hand | `RightArm -> RightForearm -> RightHand` | 19 | 7 |
| `RightLeg` | hip through foot | `RightLeg -> RightLowerLeg -> RightFoot` | 14 | 5 |
| `Body` | pelvis and chest | `Hip -> Chest` | 21 | 8 |
| `LeftLeg` | hip through foot | `LeftLeg -> LeftLowerLeg -> LeftFoot` | 15 | 4 |
| `Head` | rigid upper head | `Head` | 14 | 1 |
| `Chin` | lower face/jaw | `Chin` | 7 | 1 |
| `LeftArm` | shoulder through hand | `LeftArm -> LeftForearm -> LeftHand` | 20 | 7 |

The scene-tree order above is also the back-to-front draw order. The far arm
and far leg are behind `Body`; the near leg, head, chin and near arm are in
front. This is part of the assembly, not accidental atlas placement.

Every polygon selects the same `Skeleton2D` with
`skeleton = NodePath("../../Skeleton2D")`. Its individual bone paths are then
stored relative to that skeleton root, for example
`Hip/Chest/RightArm/RightForearm`.

## Kotone asset contract

The M01 front mannequin atlas must contain these six independent transparent
islands. Names are anatomical, not viewer-relative:

1. `body` — continuous pelvis, abdomen and chest;
2. `head` — complete neutral head and neck silhouette;
3. `arm_right` — one continuous shoulder-to-fingertips texture;
4. `arm_left` — one continuous shoulder-to-fingertips texture;
5. `leg_right` — one continuous hip-to-toes texture;
6. `leg_left` — one continuous hip-to-toes texture.

The demo's seventh `Chin` polygon is documented but intentionally deferred:
jaw motion is unrelated to the M01 locomotion proof. M02 or the later face pass
may add `face_lower` without changing the six-part body contract. Hair, clothes,
badge and facial expressions are later overlays and are not part of this
neutral mechanics atlas.

The existing 15 cutout PNGs remain useful only for locating Kotone's approved
joint centers and reconstructing her neutral proportions. They are not the
source topology for the new weighted rig. In particular, do not assemble a
production arm from separate upper-arm, forearm and hand rectangles or a leg
from separate thigh, calf and foot rectangles.

## Skeleton contract

```text
pelvis
├── torso
│   ├── head
│   ├── upper_arm_right
│   │   └── forearm_right
│   │       └── hand_right
│   └── upper_arm_left
│       └── forearm_left
│           └── hand_left
├── thigh_right
│   └── calf_right
│       └── foot_right
└── thigh_left
    └── calf_left
        └── foot_left
```

M01 uses 15 bones; an optional `face_lower` child of `head` restores the demo's
sixteenth jaw bone when facial motion begins. Bone
origins must sit on Kotone's anatomical joints. After the hierarchy and neutral
T-pose are final, use **Overwrite Rest Pose** in Godot.

## Mesh-authoring method copied from the example

Copy the method, never the robot coordinates:

1. Import one approved transparent Kotone atlas.
2. Create the six M01 `Polygon2D` nodes in the required draw order.
3. Trace each Kotone island in the Polygon2D UV editor.
4. Add internal points around every bending zone.
5. Draw explicit cells across shoulder, elbow, wrist, hip, knee, ankle and the
   torso waist transition; do not accept automatic triangulation blindly.
6. Assign the common `Skeleton2D` to every polygon.
7. Use **Sync Bones to Polygon** in the editor. Do not type serialized bone
   paths by hand.
8. Paint full weights over rigid regions and shared weights only across the
   local joint rows. Paint newly added internal points too.
9. Animate `Bone2D` transforms only. Never animate Polygon2D geometry or node
   rotation as the normal locomotion mechanism.

The official arm uses local `0.5/0.5` transitions at elbow and wrist. The legs
and torso use slightly asymmetric transition weights, including `0.53`,
`0.51` and one small `0.03` correction. These values prove that final tuning
may be asymmetric; they are not values to paste into Kotone.

## Build gates

1. **Atlas gate:** all six M01 islands exist, have real transparency and
   reproduce the approved neutral silhouette when assembled.
2. **Neutral binding gate:** all six polygons render at rest with no gaps,
   clipping, unpainted vertices or unexpected displacement.
3. **Component gate:** test both arms, both legs, torso and head
   separately while the others remain visible as context.
4. **Articulation gate:** test shoulders, elbows, wrists, hips, knees, ankles,
   waist, neck and optional jaw through the ranges needed for locomotion.
5. **Whole-body gate:** reproduce idle, walk, run and jump mechanics using the
   same class of bone tracks as the official character.
6. **Clothing gate:** only after the neutral mannequin walks correctly may
   clothes and secondary layers be added.

At every visual gate render checker, dark and magenta backgrounds. A validator
passing is necessary but cannot approve a distorted silhouette.

## When a mutation experiment is justified

Swapping arms and legs is not currently useful: the scene already proves that
polygons bind by bone path and that UV islands are independent of scene-tree
placement. If a later editor-authored Kotone polygon fails, make a disposable
copy and swap only one controlled variable:

- bind the known-good gBot arm polygon to the opposite arm chain to test path
  resolution;
- replace one gBot texture island while retaining its mesh to test UV
  registration;
- retain Kotone geometry but re-run **Sync Bones to Polygon** to test binding.

Never commit a deliberately scrambled character to the production scene.

## Authoritative references

- `reference_projects/godot_skeleton2d_demo/player/player.tscn`
- `reference_projects/godot_skeleton2d_demo/player/gBot.png`
- [Godot 2D skeleton tutorial](https://docs.godotengine.org/en/stable/tutorials/animation/2d_skeletons.html)
- [Godot Polygon2D class](https://docs.godotengine.org/en/stable/classes/class_polygon2d.html)
- [Godot Skeleton2D class](https://docs.godotengine.org/en/stable/classes/class_skeleton2d.html)
