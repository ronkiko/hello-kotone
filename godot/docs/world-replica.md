# Authoritative World Replica — v3.main.5.03

`scripts/mmo/world_replica.gd` is a RefCounted public-data reducer with no socket,
server imports, scene nodes or Sprite2D references. MmoClient owns one persistent
`world_replica`; scenes read copies and subscribe to its `changed` signal.

`view()` returns status, epoch/revision, map reference, players indexed by ID,
local player ID, confirmed local X, stale_reason, resync_required and
reconnect_required. `snapshot()` and `local_player()` also return deep copies;
changing these copies never changes confirmed data. There is no prediction or
client-selected X in the reducer.

`start(snapshot, player_id, nickname)` establishes enter baseline N. Events can
arrive before map; `install_map()` then checks map identity/hash and all current
player bounds. Once the map is known, every snapshot/event checks local/remote X.
`apply_event()` accepts exactly N+1 in the same zone/epoch. Joined inserts an absent
ID, moved updates an existing position without renaming, and left removes an
existing remote player. IDs/nicknames remain unique, snapshots sorted and bounded
(128 players), and the local player present. Invalid updates preserve all data.

## Resync and failure

On a healthy connection, explicit `MmoClient.request_state()` changes lifecycle
to RESYNCING and replica to STALE/RESYNC_PENDING. Preceding events still reduce;
the correlated state reply replaces the full snapshot and restores SYNCED/READY.
Subsequent events must be snapshot revision+1. Nothing is buffered or replayed.
The snapshot retains zone/map, epoch, local identity and nondecreasing revision.
`world_ready` is emitted only for initial entry, not refresh.

Duplicate, gap, wrong epoch/zone, bad membership or invalid positions invalidate
the stream. Replica becomes STALE with resync/reconnect required; MmoClient raises
STREAM_DESYNC and closes/fences the connection. State cannot repair a corrupt TCP
stream: this follows `ai_research/v3/game/docs/protocol.md`. Invalid snapshots
also close the connection. Last confirmed data remains available only as stale.
Explicit new Login/enter clears the old sequence and establishes a fresh baseline;
only this accepts a new epoch. Old-epoch events cannot update it. Confirmed logout
clears replica to EMPTY. Automatic reconnect/retry remains absent (patch 08).

World reads nickname/zone/X and offers Refresh world. Refresh/Leave are disabled
during resync. Standalone movement is not connected; rendering remains patch 04.

## Checks

From `ai_research`:

```sh
python3 v3/game/op/check-client-replica.py --project ../hello-kotone/godot --require-committed
python3 v3/game/op/check-client-wire.py --project ../hello-kotone/godot --require-committed
python3 v3/game/op/check-client-shell.py --project ../hello-kotone/godot --desktop --require-committed
```

Reducer checks cover atomicity, defensive copies, snapshot replacement, strict
membership/sequence/epoch, map bounds, population cap and stale disconnect state.
Real shared Game runs two Godot public peers: observer MmoClient and an
acceptance-only peer sending player2 enter/move/logout on protocol v4. Python
only orchestrates services/processes. Fixtures cover loading events, events
before/after state in one TCP write, corrupt sequences, invalid snapshots and
explicit reentry with a new epoch. Request counts prove no hidden retry/reconnect
or state repair. UI checks activate Refresh and verify scene/session preservation.
