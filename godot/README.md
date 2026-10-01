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

## MMO integration — v3.main.5.02

`MmoClient` is a persistent Autoload with direct protocol-v4 TCP/JSONL Login/Game
connections. The project now starts at Login: choose a nickname (default player1),
set the local Login endpoint and press Connect. Loading stages lead to a separate
World scene after the map and state have been validated. Leave world waits for
logout and returns to Login. The Kotone renderer is not connected yet.
The shared roadmap lives in the neighboring `ai_research` repository, under
`v3/docs/roadmap/v3/main/5/`. This client checkout is `~/work2/hello-kotone`.
See [MMO wire core and checks](docs/mmo-wire.md) for the API and validation commands.
See [Login/Loading shell](docs/login-shell.md) for startup and UI acceptance.
The build order above describes the earlier standalone prototype; the active MMO
integration order is defined by series 5 in `ai_research`.
