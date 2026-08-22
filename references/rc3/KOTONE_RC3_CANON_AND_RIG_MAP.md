# KOTONE RC3 — CANON AND DEFORMABLE 2D RIG MAP

Status: mandatory RC3 production specification

Initial view: front

Rest pose: front-facing T-pose

Rig method: weighted `Polygon2D` meshes driven by `Skeleton2D`

## 1. Source priority

When sources disagree, use this order:

1. The decisions in this document.
2. An explicitly user-approved RC3 front T-pose source.
3. RC2 artwork for rendering style, adult body proportions, clothing and materials.
4. RC1 portrait artwork for face identity and expressions only.
5. Old passports and atlases as non-binding references only.

The archived Task 3/Task 4 rigid-cutout experiment is not a production source:
`godot/archive/rc3_rigid_cutout/`.

## 2. Binding visual style

Kotone uses the polished, detailed, semi-realistic anime rendering visible in
the RC2 idle and walk artwork. Preserve dimensional skin, hair, fabric, tights
and shoe shading and adult anatomy.

Production artwork must never use flat vector illustration, cartoon clip-art,
chibi or childlike proportions, simplified cel shading, toy-like rendering,
pixel art, placeholder faces or mitten hands. A correct pose in the wrong style
is rejected.

## 3. Character canon

### Body

- Young adult anime woman; never a child or schoolgirl.
- Adult feminine proportions based on RC2.
- Long legs, compact torso and natural curves.
- Stable head, shoulder, waist, hip, hand and foot scale.
- Exactly two complete arms, two hands, two legs and two feet.

### Face and hair

- Soft oval face, small nose and mouth, pink-violet eyes.
- Face identity follows the RC1 portrait sheet, rendered at RC2 quality.
- Pastel pink jaw-length bob with straight bangs.
- No earrings, necklace or side-specific jewelry.

### Clothing

- White office blouse with sleeves rolled consistently to just below the
  elbows, exposing both forearms.
- Dark fitted vest.
- One coherent fitted short black pencil skirt.
- Pronounced front slit revealing the tights behind it; it is never a black
  plug or an alpha hole.
- Separate rear walking vent belongs to later rear artwork.
- Dark semi-transparent tights.
- Matching black pumps with moderate narrow heels.
- The skirt must never turn into shorts or two separate leg holes.

### Accessories

- Centered blue lanyard and small blank rectangular badge.
- Lanyard and badge remain separable secondary elements in the later rig.
- No handbag, wristwatch, bracelets or permanent hand-held object.
- No text or asymmetric symbol on the badge.

## 4. View and naming policy

The first RC3 production rig is `kotone_front`.

- Its rest source is a true front-facing T-pose.
- Left and right always mean Kotone's anatomical left and right. In a front
  view, Kotone's right appears on the viewer's left.
- Side and back artwork require later independent sources and rigs.
- Do not rotate, squash or perspective-warp the front rig to imitate another
  direction.

## 5. Front T-pose source contract

Active source path:
`godot/assets/rc3/rig/source/kotone_front_t_pose.png`.

Required construction:

- head and torso face directly forward;
- shoulders are level;
- both arms extend horizontally at shoulder height;
- elbows and wrists are straight but not hyperextended;
- both complete hands remain visible;
- legs are straight in a modest, symmetrical hip-width stance;
- a continuous background gap separates the inner silhouettes of the left and
  right legs from the skirt hem through both shoes;
- knees and feet face forward;
- hair, fingertips and heels remain inside the canvas with safe margins;
- production PNG uses genuine alpha and contains no checkerboard pixels,
  backdrop, floor, shadow, labels or guides.

The T-pose must be generated as one coherent character. Do not mechanically
assemble it from the archived incompatible limb PNGs.

## 6. Rig method

Use `Skeleton2D`/`Bone2D`, textured `Polygon2D` regions and vertex weights
shared across joints for continuous bending. Separate overlay layers are
allowed only where expressions, hair or accessories need independent motion.

Do not rebuild the character as rigid upper-arm, forearm, thigh and calf
`Sprite2D` chains. That experiment failed because independently generated
segments did not share compatible joints or hidden overlap.

## 7. Planned mesh regions

Back to front, subject to validation:

1. `hair_back`
2. `leg_left`
3. `leg_right`
4. `torso_skirt`
5. `arm_left`
6. `arm_right`
7. `head_neck`
8. `hair_front`
9. `face_overlays`
10. `lanyard_badge`

This is a plan, not permission to cut the source immediately. Region boundaries
are authored only after the T-pose source is approved.

## 8. Skeleton plan

```text
root
└── pelvis
    ├── torso
    │   ├── neck
    │   │   └── head
    │   ├── shoulder_left
    │   │   └── elbow_left
    │   │       └── wrist_left
    │   ├── shoulder_right
    │   │   └── elbow_right
    │   │       └── wrist_right
    │   └── badge_control
    ├── hip_left
    │   └── knee_left
    │       └── ankle_left
    └── hip_right
        └── knee_right
            └── ankle_right
```

Hair controls are added only when the corresponding region exists.

## 9. Mandatory artwork QA

Every production source or extracted texture must be checked at original
resolution and on checkerboard, dark and magenta backgrounds. Verify genuine
RGBA, absence of baked backgrounds and colored/white halos, safe margins,
plausible hands and joints, correct limb count, binding RC2 style and all canon
exclusions. Formal channel or dimension checks never replace visual inspection.

## 10. Stage gates

1. `front_t_pose_source_ready_for_review` — source and QA previews exist.
2. `front_t_pose_source_approved` — user explicitly approves the source.
3. `single_limb_mesh_spike_approved` — one weighted limb bends cleanly.
4. `full_neutral_rig_approved` — complete front rig passes visual QA.
5. `animation_authoring_allowed` — only then may idle/walk work begin.

No agent may silently promote a stage. A generated T-pose is not approved until
the user accepts it.
