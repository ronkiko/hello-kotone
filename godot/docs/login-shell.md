# Login & Loading shell — v3.main.5.02

`project.godot` starts `scenes/mmo/login.tscn`. Nickname defaults to `player1`;
the local development Login address is `127.0.0.1:24000`. These are editable
fields, not a second endpoint configuration hidden in code. Game is discovered
from the validated Login response.

Connect explicitly starts the existing MmoClient wire flow. Fields/Connect are
disabled while connecting; Cancel closes the connection. Status text follows
CONNECTING_LOGIN → AUTHORIZING → CONNECTING_GAME → ENTERING_WORLD → LOADING_MAP →
LOADING_STATE → READY. No raw server messages, tickets or session IDs are displayed.
Failures leave Connect enabled for a manual retry. Lost mutation replies show
that the server outcome is unknown; the UI never retries automatically.

Only `world_ready`, after validated map and state, schedules the World scene.
The transition checks READY again before replacing the scene so that a late fault
cannot open World. MmoClient remains the same Autoload instance throughout.
Patch 03 adds confirmed local position from WorldReplica and Refresh world
(explicit state resync). Leave world remains the logout action.
Patch 04 renders the platform and Kotone from verified map/confirmed position.
Patch 05 enables bounded A/D or arrow intentions, confirmed-target smoothing
and visible nonterminal move rejections. Release a rejected key before retrying.

Leave world requests public logout, waits for its response and returns to Login.
A lost logout reply returns with an unknown-outcome message; FLUSH_FAILED remains
a known rejection. Window close simply ends the connection and is not a confirmed
logout. The earlier local prototype remains available as `scenes/main.tscn`.

## Run

From the neighboring `ai_research` checkout, start an isolated development stand:

```sh
./v3/game/op/stand.sh init client02 --profile shared
./v3/game/op/stand.sh run client02
```

`init` is needed once; reuse `run` on later launches. Wait for Storage/Login/Game
READY. In another terminal:

```sh
~/.local/bin/godot --path ~/work2/hello-kotone/godot
```

Connect `player1`. Try `stranger` to see the nickname rejection. Stop the stand
to exercise the offline error. Leave world returns to Login through logout.

## Checks

From `ai_research`:

```sh
python3 v3/game/op/check-client-shell.py --project ../hello-kotone/godot --desktop --require-committed
python3 v3/game/op/check-client-wire.py --project ../hello-kotone/godot --require-committed
```

The shell suite loads the actual shipped scenes and activates their controls.
It starts real Storage/Login/Game on temporary ports/SQLite, checks lifecycle,
offline and nickname errors, manual retry, cancellation, map validation and
logout failures. Negative fixtures also check no automatic replay/reconnect.
The desktop case opens a real rendered window and captures startup, rejection,
World and return to Login. Omit `--desktop` on a machine without a display.
Python only orchestrates tests; there is no gameplay proxy. Evidence goes to the
printed temporary directory. Final reports record the exact clean committed SHA
pair; author acceptance for the full series remains patch 09.

Scene replacement follows the [Godot SceneTree API](https://docs.godotengine.org/en/stable/classes/class_scenetree.html#class-scenetree-method-change-scene-to-file).
