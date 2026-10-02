# Map cache and 1D presentation — v3.main.5.04

Enter establishes the map reference in WorldReplica. MmoClient checks
`user://mmo/maps-v1`: a hit must pass the same strict JSON/schema/canonical SHA-256
validation as the public map response and match ID, version and hash. A missing,
truncated, oversized, duplicate-key or mismatched file is a miss, followed by the
ordinary public map request. Invalid network maps remain terminal failures.
A hit still installs map bounds into WorldReplica and requests state: it does
not skip readiness or revision checks. Explicit request_map still contacts Game.

Cache keys hash the complete reference; map IDs never become file paths. Compact
JSON files contain no newline (Protocol.decode receives frames without LF).
Writes use a temporary file and rename. Disk write failure affects reuse only;
a validated live map remains usable. Each read is capped at the wire frame budget.

World shell adapts replica.changed to platform_world.project(map, replica.view()).
The renderer has no sockets, raw responses, GameState/current_room, input or
server imports. It keeps copies and projects confirmed local X with:

```
meters = (x - min_x) / units_per_meter
pixel_x = 32 + meters * 8
```

Thus apartment/street/work span 800/1600/400 pixels. Exact boundary walls use min/max;
work's nonzero min_x is subtracted. The same fixed scale applies to all zones.
The existing Kotone scene supplies art; its standalone movement controller is
removed from that instance. Idle frames animate without changing X. Camera2D
follows the confirmed position and stays within padded world bounds. The smaller
work zone fits both boundary walls into the viewport.

The local SVG atlas supplies a TileSet used by TileMapLayer. Only the visible
strip is built, with local cell coordinates: legal large maps cannot allocate
an entire world or overflow serialized tile coordinates. Viewport resize rebuilds
the strip and updates the camera after deferred UI layout. Refresh updates the
projection, preserves the scene/session and does not replay events.

This is deliberately a simple repeated platform/background. Patch 05 adds human
input outside the renderer and smooth movement toward confirmed targets. Remote characters are implemented in [patch 07](multiplayer-presentation.md);
reconnect remains patch 08. Prediction is now a separate
bounded display target in [patch 06](prediction-reconciliation.md).

## Run

From ai_research, initialize `client04` once using `--profile zones`, then run it:

```sh
./v3/game/op/stand.sh init client04 --profile zones
./v3/game/op/stand.sh run client04
```

In Godot, open this project's project.godot and press F6 on Login or F5 for the
project. The endpoint remains 127.0.0.1:21060. player1/player2/player3 start in
apartment/street/work on a fresh zones stand. Existing saves retain their zones.
Leave world before switching nickname. Shared stands place all three in apartment.

## Acceptance

From the neighboring ai_research checkout:

```sh
python3 v3/game/op/check-client-presentation.py --project ../hello-kotone/godot --desktop --require-committed
```

Tests isolate XDG_DATA_HOME per Godot process; operator/user caches are untouched.
Within each process, explicit reentries test cold/warm/hash/schema/duplicate-key/
oversized/wrong-reference files. A public fixture audits actual requests: seven
entries, six map requests, seven state requests, no automatic reconnect/replay.
Real Storage/Login/Game in a zones stand confirm all three lengths/spawns and
capture the shipped World UI. Pure checks cover scale, min offset, bounds, idle
input isolation, resizing and bounded huge-map rendering. Desktop acceptance
requires a display; omit --desktop for headless checks.

API reference: [TileMapLayer](https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html),
[TileSetAtlasSource](https://docs.godotengine.org/en/stable/classes/class_tilesetatlassource.html).

The floor coordinate ruler uses absolute server X and map units_per_meter. Only
visible ticks are drawn, with adaptive spacing for dense/large maps. Gold highlight
and X tag mark confirmed local X; sprite interpolation/prediction cannot move it.
