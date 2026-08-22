# Hello Kotone: Godot

This is the new RC3 Godot 2D implementation of Hello Kotone.

The original browser implementation remains in `../legacy/web/` and is used
as a behavior and visual reference only. This project is intentionally built
from scratch rather than converted from the Canvas implementation.

## Current milestone

- Godot 4 project configuration
- Fixed 482x270 logical viewport
- Pixel-oriented rendering settings
- Main scene with world, camera, and UI layers
- Initial global game state singleton
- RC3 rigid-cutout experiment archived
- Fresh front-facing T-pose/Polygon2D rig workspace prepared

## Planned build order

1. Player scene and horizontal movement
2. Kotone sprite import and animation
3. Hallway composition and camera follow
4. Letters and door interaction
5. Rooms 2C and 3C
6. Timer, bell, dialogue, and henshin flow
7. Audio, settings, and mobile controls
