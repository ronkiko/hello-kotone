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

## MMO clock contract — unified Realm tick

**2026-10-12 target:** one authoritative `realm_tick` per Realm epoch, shared by all server Zones; Zone only tracks committed progress. Godot client physics/prediction/animation remain local clocks, not server authority. Motion snapshots are nominally one per three Realm ticks (60/20 Hz), with real-time 20-Hz cap and explicit committed tick; damage and lifecycle events are independently ordered. Server OS monotonic is for scheduling/real latency, never gameplay variable `dt`.

See [client agent rules](AGENTS.md), [Godot timing contract](godot/README.md), and server-side [new 8.12 task](https://github.com/ronkiko/ai_research/blob/main/v3/docs/roadmap/v3/main/8/12-unified-realm-tick.md). The current per-Zone `simulation_tick` is pre-migration code, not a second canonical clock.

## Godot

Open `godot/project.godot` in Godot 4.x. Gameplay is being built from scratch;
the RC3 work currently includes character-rig experiments and reference scenes.

## Local deferred materials

`.logacy/3d-models/` holds deferred 3D-model downloads locally. `.logacy/`
is ignored by Git and is separate from the existing `.legacy/web/` archive.

Godot `.import` sidecars and script `.uid` files are versioned with their
source assets. Generated `.godot/` caches are ignored in all project folders.
Root `opencode.json` is a local MCP configuration and is also ignored.
