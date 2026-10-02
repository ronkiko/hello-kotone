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

## MMO integration — v3.main.5.08

`MmoClient` is a persistent Autoload with direct protocol-v4 TCP/JSONL Login/Game
connections. The project now starts at Login: choose a nickname (default player1),
set the local Login endpoint and press Connect. Loading stages lead to a separate
World scene after the map and state have been validated. Leave world waits for
logout and returns to Login. World now renders Kotone on a TileMapLayer platform from the verified server map.
`WorldReplica` reduces snapshot/events independently of scenes and stores confirmed
positions. World projects confirmed local X into pixels, follows with Camera2D,
and offers explicit Refresh world through state. Verified maps persist in user://;
corrupt or mismatched cache files trigger a public map request. A/D and arrows now send bounded left/right intentions to Game. Own moved facts
set confirmed X; matching receipts do not apply another step. Kotone smoothly
follows one bounded speculative display step after an accepted intention.
Prediction stays separate from WorldReplica; own facts/rejections reconcile it,
and unknown outcomes clear speculation and fence the connection without replay.
Other online players now appear from WorldReplica snapshot/joined, smoothly
follow confirmed moved targets, and disappear on left. Nickname labels and stable
tints distinguish remote players. Only the local player has input/prediction and
owns the camera. The standalone local controller stays detached in MMO World.
Faults freeze presentation and return to Login with in-memory endpoint fields
and an explicit Reconnect control. New tickets/snapshots replace old sessions;
unknown moves are never replayed, and held input requires release after reentry.
The shared roadmap lives in the neighboring `ai_research` repository, under
`v3/docs/roadmap/v3/main/5/`. This client checkout is `~/work2/hello-kotone`.
See [Explicit recovery](docs/recovery.md) for reconnect, epoch and map failure rules.
See [MMO wire core and checks](docs/mmo-wire.md) for the API and validation commands.
See [Login/Loading shell](docs/login-shell.md) for startup and UI acceptance.
See [Human movement](docs/human-movement.md) for controls, outcomes and tests.
See [Multiplayer presentation](docs/multiplayer-presentation.md) for two-window play and checks.
See [Prediction/reconciliation](docs/prediction-reconciliation.md) for latency and failure behavior.
See [Map cache and presentation](docs/map-presentation.md) for projection/cache rules.
See [World replica](docs/world-replica.md) for reduction/resync rules and checks.
The build order above describes the earlier standalone prototype; the active MMO
integration order is defined by series 5 in `ai_research`.
