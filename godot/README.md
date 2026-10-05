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

## Current MMO client — v3.main.7.09

Current public protocol is **v7**. The startup shell supports Account Login →
Realm Directory → Realm Lobby → Character Creator/Selection → World, with two
one-time handoffs. `Preworld` owns account/Lobby authority; `MmoClient` owns only
the selected-character Game visit. Leave World stops held input, waits for logout
and confirmed save/Registry completion, then returns to the same realm roster.
Back clears realm authority; account logout clears all visits. There is no v6
nickname Login or direct reconnect path.

Secure server uses certificate-verified native TLS for Login/Lobby/Game without
plaintext fallback. Local development accepts only literal loopback and dev accounts
`dev1`–`dev3`. Passwords, handoff/session secrets stay in RAM and never become UI
status text or preferences. Creator, own avatar and remote avatars share the same
local semantic appearance mapping; physics remains server-authoritative.

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
