# KOTONE RC3 — CANON AND 2D RIG MAP

Status: approved source specification for RC3 production  
Scope: visual canon, right-facing cutout rig, mirroring policy and layer map  
Not included: finished body-part artwork, Godot scene, animation curves or exported sprite sheets

## 1. Source priority

When sources disagree, use this order:

1. The decisions in this document.
2. RC2 artwork for body, clothing, silhouette and movement proportions.
3. RC1 portrait sheet for face identity and expressions only.
4. RC2 idle sheets for neutral joint placement and front/back construction.
5. The old passport and old atlases as non-binding references only.

Do not copy a contradiction from a lower-priority source into RC3.

## 2. Character canon

Kotone is a young adult anime woman with a polished office appearance. She is not chibi and must not read as a child or schoolgirl.

### Body

- Adult feminine proportions based on RC2 walk.
- Stable head, shoulder, waist, hip, hand and foot scale.
- Long legs, compact torso and moderate natural curves.
- No frame-to-frame changes to bust, waist, hips or limb length.
- Neutral upright posture with relaxed shoulders.

### Face and hair

- Face identity and expression language follow the RC1 portrait sheet `1 - ChatGPT Image Aug 21, 2026, 06_35_56 PM.png`.
- Soft oval face, small nose and mouth, pink-violet eyes.
- Pastel pink jaw-length bob with straight bangs.
- Hair volume and length remain stable; only secondary tips may sway.
- No earrings, necklace or side-specific jewelry in the rig.

### Clothing

- White office blouse with sleeves rolled consistently to just below the elbows.
- Dark fitted vest and matching fitted short pencil skirt.
- Dark semi-transparent tights.
- Black elegant pumps with a moderate narrow heel.
- The skirt remains a skirt: it must not turn into shorts between views or poses.
- The skirt slit and tailoring must remain symmetrical and direction-safe.

### Accessories

- No handbag.
- No wristwatch or bracelets.
- No permanent object in either hand.
- Keep the centered blue lanyard and small rectangular ID badge.
- Lanyard and badge are separate rig elements and are never painted into the torso.

## 3. Direction policy

The first production rig is `kotone_side_right`.

- `kotone_side_left` is produced by horizontal mirroring of the approved right-facing rig.
- Mirroring is allowed because the RC3 design contains no side-specific accessories.
- Text or asymmetric symbols are forbidden on the badge.
- Front and back views must use separate rigs later. Do not rotate or squash the side rig to imitate front/back views.

## 4. Rig method

Use a rigid cutout rig for the first prototype:

- Godot `Skeleton2D` and `Bone2D` for hierarchy;
- transparent `Sprite2D` parts attached to bones;
- no mesh deformation in the first walk prototype;
- optional `Polygon2D` deformation only after the rigid prototype reveals a specific seam that cannot be hidden by overlap.

All source parts are prepared on one authoring coordinate system. Export each part as a trimmed transparent PNG and store its canvas offset and pivot in a manifest. Do not rescale individual parts independently after cutting.

Recommended authoring canvas: `1024 x 1024`, with the full neutral character approximately centered and standing on a fixed ground line. Final game export size is decided at integration time and must not redefine proportions.

## 5. Skeleton hierarchy

```text
root
└── pelvis
    ├── torso
    │   ├── neck
    │   │   └── head
    │   │       ├── hair_back_control
    │   │       ├── hair_near_control
    │   │       └── hair_far_control
    │   ├── shoulder_near
    │   │   └── elbow_near
    │   │       └── wrist_near
    │   ├── shoulder_far
    │   │   └── elbow_far
    │   │       └── wrist_far
    │   └── badge_control
    ├── hip_near
    │   └── knee_near
    │       └── ankle_near
    └── hip_far
        └── knee_far
            └── ankle_far
```

The root controls translation through the game world. Walk-cycle bounce belongs primarily to the pelvis and must stay subtle.

## 6. Required artwork layers

| ID | Layer | Attached bone | Required overlap |
|---|---|---|---|
| 01 | `hair_back` | `head` | Hidden under head and torso collar |
| 02 | `arm_far_upper` | `shoulder_far` | Extends beneath torso at shoulder and beneath forearm at elbow |
| 03 | `arm_far_forearm` | `elbow_far` | Extends beneath upper arm and hand |
| 04 | `hand_far` | `wrist_far` | Wrist overlap under forearm cuff/edge |
| 05 | `leg_far_thigh` | `hip_far` | Hip end reconstructed beneath skirt; knee overlap beneath calf |
| 06 | `leg_far_calf` | `knee_far` | Extends beneath thigh and shoe at ankle |
| 07 | `shoe_far` | `ankle_far` | Includes complete pump and heel, with ankle overlap |
| 08 | `torso` | `torso` | Includes blouse/vest core and reconstructed shoulder sockets |
| 09 | `pelvis_skirt` | `pelvis` | Covers both reconstructed hip joints; does not include thighs |
| 10 | `leg_near_thigh` | `hip_near` | Same construction as far thigh |
| 11 | `leg_near_calf` | `knee_near` | Same construction as far calf |
| 12 | `shoe_near` | `ankle_near` | Same construction as far shoe |
| 13 | `arm_near_upper` | `shoulder_near` | Rolled sleeve remains part of upper arm |
| 14 | `arm_near_forearm` | `elbow_near` | Skin forearm with hidden elbow overlap |
| 15 | `hand_near` | `wrist_near` | Complete relaxed hand, not fused to forearm |
| 16 | `neck` | `neck` | Hidden overlap under torso collar and head |
| 17 | `head_base` | `head` | Face skin without eyes, eyebrows or mouth |
| 18 | `eye_near_open` | `head` | Expression overlay |
| 19 | `eye_near_closed` | `head` | Blink overlay |
| 20 | `eye_far_open` | `head` | Side-view far eye if visible |
| 21 | `eye_far_closed` | `head` | Blink overlay if visible |
| 22 | `brows_neutral` | `head` | Separate expression overlay |
| 23 | `mouth_neutral` | `head` | Separate expression overlay |
| 24 | `mouth_smile` | `head` | First alternate expression |
| 25 | `hair_front` | `head` | Bangs and front hair contour above face elements |
| 26 | `hair_near_tip` | `hair_near_control` | Small secondary sway only |
| 27 | `hair_far_tip` | `hair_far_control` | Small secondary sway only |
| 28 | `lanyard` | `badge_control` | Top anchored at neck/chest center |
| 29 | `badge` | `badge_control` | Separate from lanyard when practical |

For the initial walk proof, mouth and eye alternatives may remain static, but the layer structure must not prevent later expressions.

## 7. Default draw order

Back to front:

1. `hair_back`
2. far arm
3. far leg
4. `torso`
5. `pelvis_skirt`
6. near leg
7. near arm
8. `neck`
9. `head_base` and facial overlays
10. `hair_front` and hair tips
11. `lanyard`
12. `badge`

Near/far leg draw order must swap at the passing point of the walk cycle. Animate `z_index`; do not redraw alternate legs merely to fake crossing.

## 8. Pivot rules

- Shoulder pivot: anatomical center of the shoulder joint, inside the torso overlap.
- Elbow pivot: center of elbow bend, hidden by overlap in every allowed angle.
- Wrist pivot: wrist center, never at the palm center.
- Hip pivot: anatomical hip socket under the skirt, not at the visible skirt edge.
- Knee pivot: center of knee articulation.
- Ankle pivot: ankle joint above the shoe, not at the heel or toe.
- Head pivot: base of skull/upper neck.
- Badge pivot: centered near the lanyard attachment, allowing a very small delayed swing.

Every limb segment must contain enough reconstructed hidden artwork around its joint to rotate at least the expected walk range without exposing a transparent hole.

## 9. Walk constraints carried into animation

- One complete cycle contains left and right contact, down, passing and up phases.
- Feet alternate; the same leg may not perform both consecutive steps.
- The planted foot does not slide during its contact interval.
- At least one foot supports the body throughout normal walking.
- Pelvis vertical movement is subtle; no horse-like gallop or hopping.
- Arms swing opposite the legs from the shoulders, with a smaller forearm follow-through.
- Knees remain moderate and appropriate for walking in heels.
- Head movement is restrained and follows the torso with minimal delay.
- Hair, lanyard and badge use low-amplitude secondary motion only.

## 10. Source usage for cutting

| Source | Allowed use | Forbidden use |
|---|---|---|
| RC2 walk right | Side silhouette, torso, limbs, shoes and clothing style | Reusing its six poses as the final animation |
| RC2 idle right/left | Neutral joint placement and relaxed posture | Copying its conflicting long sleeves into RC3 |
| RC2 idle back | Back construction without bag/watch | Treating its small render as final-resolution artwork |
| RC1 front idle | Front body and face relationship | Importing any inconsistent jewelry |
| RC1 portrait sheet | Face identity, eyes, mouth and expressions | Body proportions, clothing details or accessories |
| RC1 back sheet | Hair/back tailoring reference only | Bag, watch, body parts or final pixels |
| Old atlas sheets | Pose vocabulary only | Pixel source for RC3 parts |

## 11. Task 3 acceptance criteria

Task 3 is complete only when:

- all 29 required layers exist or an explicitly documented simplification is approved;
- every PNG has real alpha and no checkerboard or colored background baked in;
- red, magenta, white and gray generation halos are removed;
- hidden shoulder, elbow, wrist, hip, knee and ankle areas are reconstructed;
- parts align into one neutral right-facing character without gaps;
- no bag, watch or jewelry remains;
- sleeve length, skirt construction, tights, shoes, hair and body proportions match this canon;
- a contact sheet shows the assembled neutral character and the separated parts before Godot import.

