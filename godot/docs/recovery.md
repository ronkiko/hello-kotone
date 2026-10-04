# Explicit recovery — protocol v6

After a terminal fault the World freezes immediately and the UI returns to Login.
Every retry starts a fresh Login -> one-use ticket -> advertised Game ->
session_rules -> enter realm bootstrap + snapshot -> map/world rules/state -> READY lifecycle.

There is no automatic reconnect and no automatic mutation replay.

## Unknown input outcome

A missing `input` response does not prove whether the server installed the held
direction. The client marks the outcome unknown, fences the old connection and never
re-sends that input sequence on a new session.

Game disconnect clears the old session's held input. Fresh enter restarts input_seq at
1 and its realm-bound snapshot shows the current X; the old command outcome remains unknown.

Holding a key through failure/reentry cannot replay old movement: the new World
requires a release before fresh input.

## Healthy resync vs reconnect

`state()` is only a healthy-stream boundary. Events that precede its response keep
reducing in TCP order, but the snapshot revision must match the current reduced
revision. Gap/wrong epoch requires reconnect; state cannot heal it.

Transport callbacks are generation-fenced so a closed socket cannot mutate a newer
session.

## Presentation

STALE freezes local/remote presentation. Existing confirmed facts remain inspectable,
but old trajectory/input prediction is not carried into the fresh World scene.

Map cache remains presentation cache only. A fresh snapshot/map reference decides
which content is valid.

## Healthy idle

`session_rules` negotiates Host request/idle/keepalive policy before enter. READY idle
uses strict read-only ping with a free request slot. User input has priority over a due
ping. Pong never changes replica/revision/world_ready.

Lost/malformed pong is a known read-only failure, not an unknown movement mutation.

## Check

```bash
python3 v3/game/op/check-client-recovery.py --project ../hello-kotone/godot --desktop --require-committed
python3 v3/game/op/check-client-heartbeat.py --project ../hello-kotone/godot --require-committed
```
