# Hello Kotone: Godot

This is the new RC3 Godot 2D implementation of Hello Kotone.

The original browser implementation is archived locally in `../.legacy/web/`
when available and is used
as a behavior and visual reference only. This project is intentionally built
from scratch rather than converted from the Canvas implementation.

## Current milestone

- Godot 4 project configuration
- Fixed 482x270 logical viewport
- Pixel-oriented rendering settings
- Main scene with world, camera, and UI layers
- Initial global game state singleton
- Kotone v2 front-facing idle and left/right walking animations
- RC3 rigid-cutout experiment archived
- Fresh front-facing T-pose/Polygon2D rig workspace prepared

## Planned build order

1. Player collision and world bounds
2. Hallway composition and camera follow
3. Letters and door interaction
4. Rooms 2C and 3C
5. Timer, bell, dialogue, and henshin flow
6. Audio, settings, and mobile controls

## Current MMO client — v3.main.7.11 presentation corrective

Current public protocol is **v7**. The startup shell supports Account Login →
Realm Directory → Realm Lobby → Character Model → Fine Appearance → Selection → World, with two
one-time handoffs. `Preworld` owns account/Lobby authority; `MmoClient` owns only
the selected-character Game visit. Leave World stops held input, waits for logout
and confirmed save/Registry completion, then returns to the same realm roster.
Back clears realm authority; account logout clears all visits. There is no v6
nickname Login or direct reconnect path.

Secure server uses certificate-verified native TLS for Login/Lobby/Game without
plaintext fallback. Local development accepts only literal loopback and dev accounts
`dev1`–`dev3`. Passwords, handoff/session secrets stay in RAM and never become UI
status text or preferences. Creator, own avatar and remote avatars share the same
local Kotone/Yuna semantic appearance mapping with canonical `character_model_id`; physics remains server-authoritative.

7.10 established semantic character-model selection. 7.11 is the separate
presentation corrective that normalizes Kotone/Yuna assets and migrates the
runtime to the canonical frame/SpriteFrames path.

Raster humanoid art has a client-side machine contract:
`assets/mmo/character_sprite_frame_contract_v1.json`, loaded by
`scripts/presentation/character_sprite_frame_contract.gd`. Canonical frame is
256×256, ground-contact pivot is (128,236), baseline is y=236. Physical model
height is stored in centimeters and raster v1 uses `1 cm = 1 canonical px`:
Kotone=172 cm -> 172 px, Yuna=155 cm -> 155 px. World position and physics never
come from bitmap bounds.

Godot presentation follows native transform semantics: a CharacterRoot/Node2D owns
the world-facing position and the visual Sprite2D/AnimatedSprite2D is a child
anchored so frame pixel (128,236) maps to root (0,0). If characters need to appear
larger/smaller in a viewport, use one common parent transform or Camera2D zoom;
do not encode model/state height through per-animation scaling. AnimatedSprite2D
with SpriteFrames is the preferred future animation container once canonical
256×256 assets are normalized.

Canonical animation authoring now uses **one 256×256 RGBA PNG per frame** under
`assets/characters/<character_model_id>/<animation>/NNN.png`. Runtime animation
metadata lives in the native Godot `SpriteFrames` resource
`assets/characters/<character_model_id>/sprite_frames.tres`; manually-authored
spritesheets are no longer the target runtime format.

Minimum locomotion package animations are `idle`, `walk_left`, and
`walk_right`. The canonical offline entry point is:

```text
python godot/tools/character_assets.py doctor
python godot/tools/character_assets.py validate kotone yuna
```

The same tool provides `extract-grid`, LLM/human `inspect`, deterministic
ImageMagick `normalize`, and native Godot `build-spriteframes`.

Existing pre-contract sheets remain source/reference material until their frames
are extracted and normalized; do not add new state-specific scale compensation
for their arbitrary dimensions.

Held input, prediction/reconciliation, confirmed replica, map cache, realm identity
fencing and bounded heartbeat remain active. Unknown outcomes never replay input or
mutations; character mutation receipts reconcile only on explicit human action.

See [Current Realm Lobby flow](docs/realm-lobby.md). Shared roadmap and validation
runner are in the neighboring `ai_research` repository. Previous Series 5/6 docs
below preserve architecture/history; their old Login/admission commands are
superseded by the current flow:

- [World replica](docs/world-replica.md)
- [Map presentation](docs/map-presentation.md)
- [Human movement](docs/human-movement.md)
- [Prediction/reconciliation](docs/prediction-reconciliation.md)
- [Multiplayer presentation](docs/multiplayer-presentation.md)
