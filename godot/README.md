# Hello Kotone: Godot MMO client

Статус: **IMPLEMENTED**, public v9. [Карта клиента](../ARCHITECTURE.md) объясняет
UI, transport/session, replica, native prediction, remote timeline, frame health
и presentation. Серверные каноны находятся в ai_research; здесь локальные consumers.

## Навигация

| Область | Документ |
| --- | --- |
| Login, Directory, Lobby, roster, Creator и takeover | [Realm Lobby](docs/realm-lobby.md) |
| Network lifecycle, controls и motion | [Current wire](docs/motion-wire-v8.md) |
| Map cache и projection | [Map presentation](docs/map-presentation.md) |
| Owner prediction/reconciliation | [Prediction](docs/prediction-reconciliation.md) |
| Remote avatars, gait и damage | [Multiplayer presentation](docs/multiplayer-presentation.md) |
| Frame freshness / Visual Stall | [Frame health](docs/frame-health.md) |
| Logout, unknown outcomes и reconnect | [Recovery](docs/recovery.md) |
| Canonical frames, SpriteFrames и tooling | [Assets/tools](docs/assets-and-tools.md) |

## Запуск и границы

Open `project.godot` in Godot. `scenes/mmo/login.tscn` is the main scene;
Preworld/MmoClient persist across scene changes. The logical viewport is 482×270;
shared canvas/camera transforms do not encode different model heights.
Current MMO does not use the RC3 GameState story fields as world authority.

Beta uses certificate-verified native TLS without plaintext fallback. Local dev
allows literal loopback only. Login credentials, account/realm visits and world
handoffs have separate lifetimes. Never reuse a secret to reconnect automatically.

One server realm_tick scopes all Zone progress within an epoch. Client physics
local_ordinal, render interpolation, animation and monotonic time remain distinct.
Owner native CharacterBody2D uses the selected server body/motor profiles; remote
roots use the delayed server timeline. New scope/stale data fences prediction.
Authoritative damage is an ordered event; current HP is not implemented.

Canonical raster frames are 256×256 RGBA, pivot (128,236), 1 px/cm.
Kotone 172 cm, Yuna 155 cm; AnimatedSprite2D/SpriteFrames, shared parent display
scale 0.48, no per-animation height compensation. Server-installed profiles currently
supply Kotone 1300 mm/s / 400×1720 mm and Yuna 1820 mm/s / 360×1550 mm;
these are card values, not a second client physics table.

## Offline tools and checks

```text
python godot/tools/character_assets.py doctor
python godot/tools/character_assets.py replay-recipe godot/tools/character_recipes/locomotion_v1
python godot/tools/character_assets.py validate kotone yuna
```

Commands above run from the client repository root. Replay checks tracked sources,
hashes and exact canonical outputs in temporary storage. New uncommitted art or
recipe edits are not covered by an old successful replay.

Shared `ai_research/v3/game/op/check-client-lobby.py` orchestrates native Godot,
TLS flow, domain suites and assets checks; focused Worker recovery/handoff runners
are separate. Reports must name exact source pairs. This documentation-only audit
runs none of these game/asset commands and supplies no new runtime PASS.

Legacy RC3 and research projects retain their original scope in
[history/reference map](../../ai_research/v3/game/docs/research-and-history.md).
