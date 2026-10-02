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

`MmoClient` uses direct protocol-v5 Login/Game TCP connections. Login -> fresh
ticket -> enter -> validated map/world rules/state leads to World. A/D and arrows
publish held input changes (`input_seq`, left/right/stop); Game owns autonomous
movement cadence. Moved events update WorldReplica; ACK only confirms input state.
LocalTrajectory predicts continuously from current human intent, and server facts
correct it magnetically. Gait follows actual display distance; held local input
preserves side pose between facts, release and settling returns front idle.
Remote avatars interpolate confirmed facts and freeze the last side pose at gaps.
Floor ruler marks confirmed X independently of prediction/render X.
Failures freeze presentation and return to explicit Reconnect: new Login/ticket/
enter, no automatic input replay. Unknown input outcome remains explicit.
Host session_rules advertises request pacing/idle keepalive; read-only ping keeps
spectators online without world resync or mutations. Verified maps persist locally.
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
