# Hello Kotone

RC3 is being developed as a new Godot 2D project. The previous browser game
is archived unchanged as a runnable legacy implementation.

## Repository layout

```text
.legacy/web/                Local-only archive of the Canvas and vanilla JS game
references/                 Source and visual reference material
```

`.legacy/` is ignored by Git, so the archived browser game is present only in
working copies where it has been retained locally.

The material under `references/` is reference material, not an automatic
canonical source for RC3. Canonical art and design decisions will be declared
explicitly as the Godot project is built.

The game links on the root library page point to `.legacy/web/` when the local
archive is available. The ignored archive is not included in Git checkouts or
deployments.

## Legacy

If `.legacy/web/` is present, run the repository through a static HTTP server
and open `/.legacy/web/`:

```text
python3 -m http.server
```

The legacy implementation still uses local source material from `.local/` when
that ignored working-copy directory is available.

## MMO timing contract — Server Tick Authority

The gameplay simulation clock belongs to the server Zone, identified by `realm_instance_id / zone_package_id / zone_generation / simulation_tick`. Client Godot uses local native 60-Hz physics for owner prediction and animation, **not** as server authority. Incoming `motion_frame` is a coalescible latest committed sample, nominally 20 Hz / every three server simulation ticks, bounded by real-time cadence. Reliable gameplay damage and lifecycle events remain separately ordered. Receive/render milliseconds and network RTT are diagnostic/presentation clocks, not the time source of server physics. See [agent rules](AGENTS.md) and [Godot MMO contract](godot/README.md) for details. Canonical architecture is maintained in the neighboring private server-side `ai_research/v3/game/docs/server-tick-authority.md`.

## Godot

Open `godot/project.godot` in Godot 4.x. Gameplay is being built from scratch;
the RC3 work currently includes character-rig experiments and reference scenes.

## Local deferred materials

`.logacy/3d-models/` holds deferred 3D-model downloads locally. `.logacy/`
is ignored by Git and is separate from the existing `.legacy/web/` archive.

Godot `.import` sidecars and script `.uid` files are versioned with their
source assets. Generated `.godot/` caches are ignored in all project folders.
Root `opencode.json` is a local MCP configuration and is also ignored.
