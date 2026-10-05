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
with SpriteFrames is the active animation container for normalized canonical frames.

Canonical animation authoring now uses **one 256×256 RGBA PNG per frame** under
`assets/characters/<character_model_id>/<animation>/NNN.png`. Runtime animation
metadata lives in the native Godot `SpriteFrames` resource
`assets/characters/<character_model_id>/sprite_frames.tres`; manually-authored
spritesheets are no longer the target runtime format.

Minimum locomotion package animations are `idle_left`, `idle_right`,
`walk_left`, and `walk_right`. Last movement direction selects the stopped pose;
initial/Creator pose is `idle_right`. Both idle directions are prepared PNG
frames. Runtime does not mirror art or substitute a missing view. Asymmetric
models require independently authored directional sources. Current symmetric
Yuna uses explicit offline mirror operations recorded in the recipe; Kotone
retains front-facing art in both idle slots. The canonical offline entry point is:

```text
python godot/tools/character_assets.py doctor
python godot/tools/character_assets.py replay-recipe godot/tools/character_recipes/locomotion_v1
python godot/tools/character_assets.py validate kotone yuna
```

The raster operations are independent tools in `tools/frame_tools.py`:
`split-grid`, `extract`, `clean`, `resize`, `mirror`, `prepare`, `inspect`,
`heuristic`, `place`, `render`. An agent chooses the flow and source coordinates.
`prepare` takes physical height in cm plus px/cm, canvas, ground and pivot.
`character_assets.py` forwards these operations and provides the MMO package
validator/native Godot builder and deterministic committed-recipe replay. See
`tools/character_asset_llm_analysis.md`.

Kotone/Yuna locomotion is converted: 44 canonical PNG frames and two native
SpriteFrames resources. Creator, own and remote visuals have unit sprite scale
under the same 0.48 display transform; character roots are anchored at the floor.
Original locomotion sheets live outside the Godot runtime asset tree under
`../references/kotone/v2/` and `../references/yuna/v1/`. The shipped
`res://assets` tree contains only canonical runtime character content.
Recorded agent operations/plans and checksums are in `tools/character_recipes/`;
`replay-recipe` verifies source SHA256 and reproduces all canonical frames
byte-for-byte in a temporary directory.
Author visual acceptance is tracked in the shared 7.11 roadmap.

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
