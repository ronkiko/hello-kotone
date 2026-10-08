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

## Current MMO client — v3.main.8.08 facing, gait and presentation

Current public protocol is **v8**. The startup shell supports Account Login →
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
initial/Creator pose is `idle_right`. The owner presents its local facing
prediction; remote characters use authoritative `facing` and velocity from the
delayed motion timeline. Both idle directions are prepared PNG frames. Runtime
does not mirror art or substitute a missing view. Asymmetric models require
independently authored directional sources. Current symmetric Yuna uses explicit
offline mirror operations recorded in the recipe; Kotone retains front-facing art
in both idle slots. The canonical offline entry point is:

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

Current v8 locomotion sends bounded `control_set` desired state. The server publishes
20-Hz `motion_frame` samples with one zone-level `simulation_tick` and only
player ID, position, velocity, facing, applied control sequence and contacts.
Nickname, zone and character appearance remain on snapshots and reliable join facts;
the Godot reducer overlays motion by player ID. The input engage threshold comes
from the validated `world_rules.engage_ms` value.

Confirmed server motion remains the only gameplay authority. The local owner is a
Godot `CharacterBody2D` predicted at 60 Hz from the same complete semantic control
state sent to Game. Its bounded history retains at most 40 physics intervals and 2 s,
including intervals under an acknowledged held control. Local `local_ordinal`
starts at zero on each snapshot, independently of the server clock. An actually
sent control records its first predicted ordinal. Server-owned `control_started_tick`
names the first physics interval applying that sequence. Their first applied sample calibrates a bounded prediction lead. Subsequent samples
retire local intervals through that receive-relative mapping, so a slower server
clock cannot accumulate extra replay throughout a hold. Server tick equality
never selects local history. Older held
samples cannot confirm a pending release. Contacts and discontinuities remain
authoritative, and unknown outcomes fence prediction. Both history and the control
ledger are bounded at 40 entries; history expires after 2 seconds.
Camera follows presentation. Gait consumes integrated motion separately from
correction transforms, with a deterministic 50-ms stop debounce. Presentation
convergence cannot cancel more than the current physics displacement; a stopped
visual may retain at most 0.05 px of numerical residue without altering the body. <=2-mm native
numerical residues do not restart a visual blend on each sample. Native
`StaticBody2D` prediction-only peers use authoritative velocity hints capped at
100 ms / 250 mm; after 200 ms without a sample they stop colliding. Leave,
suspension and scope changes fence this state. No client collision becomes authority.

Remote characters use an eight-sample timeline on the server's 60-Hz
`simulation_tick`, rendered 100 ms behind the latest sample. Only authoritative
position, velocity and facing are interpolated. Extrapolation is velocity-only and
stops at 100 ms or 250 mm; contact, discontinuity, epoch, map and zone-generation
changes reset or fence the timeline. Remote roots keep Godot physics interpolation
off because its local physics clock does not define network sample time. See
[multiplayer presentation](docs/multiplayer-presentation.md).

8.08 keeps stationary facing shared and presentation-only: a short tap updates
facing with zero drive and no displacement. Owner and remote SpriteFrames gait is
driven by rendered displacement and authoritative facing; it does not infer facing
from movement or treat remote drive as known. Motion frames include a bounded
server-computed peer-contact velocity response with response-time facing, tick and
peer IDs, retained until publication. It carries no animation state. Yuna's prepared
rightward `stumble_right2` reaction plays only for an actual sufficiently strong
server contact response from behind; it remains cosmetic and cannot feed back into
physics.

See [Current Realm Lobby flow](docs/realm-lobby.md). Shared roadmap and validation
runner are in the neighboring `ai_research` repository. Previous Series 5/6 docs
below preserve architecture/history; their old Login/admission commands are
superseded by the current flow:

- [World replica](docs/world-replica.md)
- [Map presentation](docs/map-presentation.md)
- [Human movement](docs/human-movement.md)
- [Prediction/reconciliation](docs/prediction-reconciliation.md)
- [Multiplayer presentation](docs/multiplayer-presentation.md)

Series 7 final cleanup (7.14): obsolete Series 5 nickname/ticket process harnesses
were removed. The canonical real-process runner is `ai_research/v3/game/op/check-client-lobby.py`;
it executes current v8 TLS scenes, all maintained domain suites, raster tool checks
and recipe replay. Historical acceptance evidence stays in the shared roadmap.
The two Yuna art references preserved in c429a4a remain tracked source references
outside the Godot runtime asset tree.
