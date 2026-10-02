# Explicit recovery — v3.main.5.08

After a fault World freezes immediately and returns to Login. Login retains the
last valid host/port/nickname in the Autoload's memory and offers Reconnect.
Fields remain editable. Settings are not saved to disk. Every click starts a
fresh Login → new one-use ticket → advertised Game → enter snapshot → verified
map → world_rules → ordered state boundary → READY / new World scene.

There is no automatic reconnect, read-only retry or mutation replay. If Game is
still shutting down or the old presence is not yet released, an unavailable /
ALREADY_ONLINE outcome is visible; retry explicitly after the service recovers.
`reconnect_world()` is an explicit adapter API using the last valid endpoint;
Login uses `connect_world()` so edited fields are honored. Endpoint getters return
defensive copies; invalid edits do not replace the last valid endpoint.

A missing move/logout/enter response is not evidence of non-application. Unknown
outcome is visible. A received own moved fact remains confirmed even if its receipt
is lost; fresh enter is the authoritative next baseline. Prediction, ticket,
pending request and unsent intentions are discarded. Holding D through a failure
and reentry cannot send a move: release and press again in the new World scene.

`state()` is only for a healthy ordered stream. Preceding events continue reducing
while RESYNC_PENDING, but interpolation/animation pauses until SYNCED. Revision
must equal the state snapshot boundary; gaps/wrong epoch fence and require a new
Login/enter. A new epoch can only enter through a fresh cleared replica. Channel
signals bind a local generation: callbacks from a closed/replaced transport cannot
change the new connection or schedule requests. Cancellation during open/connected
callbacks leaves the socket closed and no login/enter queued.

Local and remote presentation freezes synchronously on stale replica, including
animation and camera interpolation. Existing confirmed facts remain inspectable,
but World scene is replaced with Login and freed. A fresh World uses only the new
baseline, never old interpolation targets or old membership.

The fresh snapshot's map reference controls cache reuse. A valid changed version/
hash downloads and verifies public map(); unchanged content reuses the cache.
This does not migrate checkpoints: current Game rejects an old map reference with
INVALID_MAP. UI asks the operator to restore or migrate compatible content; it
never resets saves or renders cached geometry as accepted authority. Map migration
is future obligation 5; presentation/map lifecycle review is obligation 16 in the
ai_research permanent roadmap. Live map replacement remains outside this patch.

Run from ai_research (add --require-committed for exact final evidence):

```bash
python3 v3/game/op/check-client-recovery.py --project ../hello-kotone/godot --desktop
```

The harness drives the shipped UI/A-D adapter through direct sockets, using isolated
user data and temporary service configuration/maps/SQLite. Command files coordinate
test actions only. Fault servers are deterministic wire fixtures, not a game proxy.

Manual check: run a shared/recovery stand, connect, walk, stop Game, observe Login
and retained fields. Restart Game, click Reconnect, release the movement keys, then
walk again. Refresh works on a healthy connection. If Login is stopped, retry is
visible and never loops automatically. Graceful stop flushes; abrupt process loss
may restore an earlier durable checkpoint rather than the last seen live X.
