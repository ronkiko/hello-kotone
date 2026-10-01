# Human authoritative movement — v3.main.5.05

In MMO World, hold A/D (physical keys, with logical-key fallback) or left/right
arrows. Opposing directions cancel. Release keys after entry, Refresh, focus loss
or a known rejection before starting again. The old standalone local controller
remains detached from the MMO Kotone instance.

InputAdapter samples the current key state; it owns no position, saved steps or
request queue. MmoClient.move accepts only left/right, only in READY and only
when its one scheduled/pending request slot is empty. It enters MOVING until a
receipt or a known nonterminal rejection. A 220 ms local cadence conservatively
paces the current 200 ms Game policy. Network request spacing still applies.
An accepted in-flight step may finish after key release; release creates no new
intent and no accumulated commands are drained later. Fresh held input after a
successful receipt is a new intention, not replay of a previous request.

The public payload is exactly {direction}; never X, pixels, speed or sprite data.
Own moved applies to WorldReplica before dispatch. The correlated move receipt
must match that fact's epoch/zone/revision/player_id and cannot set X again.
Receipt without an own fact, mismatch, second own moved before the receipt,
malformed response or contradictory rejection fences the connection. Remote
facts continue reducing while a move is pending.

OUT_OF_BOUNDS, RATE_LIMITED and WORLD_PAUSED are validated known move rejections:
keep session and SYNCED replica, show a bounded local UI message, and require key
release before retry. No automatic retry occurs. Lost/timed-out/cancelled move
reply has an unknown mutation outcome: retain confirmed facts as STALE, fence
the connection and require an explicit fresh Login/enter. State never repairs a
corrupt/unknown stream. A lost receipt after moved retains the new confirmed X.

PlatformWorld projects confirmed X into a target and keeps a private visual X.
It interpolates at 160 pixels/s, clamps to projected map bounds, animates existing
left/right textures per frame, and follows with Camera2D. It does not predict
from local input. Sprite2D edits cannot change that target, replica or a future
move request; the next render tick/state refresh restores presentation. First
entry snaps to the confirmed spawn; later confirmed facts move smoothly.

## Check

From ai_research:

```sh
python3 v3/game/op/check-client-movement.py --project ../hello-kotone/godot --desktop --require-committed
```

The real shared stand uses the shipped World InputAdapter and injected physical
A/D events: player1 goes spawn 50 -> min 0 -> max 100, sends an extra step at both
ends, refreshes after Sprite2D tampering, logs out and explicitly reenters at X100.
No test teleports or private server writes are used. Each move is public Game
traffic from the Godot client. Without --desktop it runs headless; the real
full-width check allows 70 seconds and retains the actual server's 200 ms limit.

Fixtures audit direction-only requests, single flight, delayed key release,
remote events, nonterminal rejections with fresh retry, malformed/missing/wrong/
duplicate receipts, second own fact, lost replies before/after moved, timeout
and synchronous cancellation. Fixture counts reject automatic replay/reconnect.
Tests isolate user data/saves. Existing wire, replica, map and UI suites remain
required regression checks.

## Later obligations

Prediction/reconciliation is patch 06, remote characters 07 and recovery/heartbeat
08. Configurable movement pacing and long-session request-budget handling are
recorded with triggers and acceptance in the shared permanent future obligations;
the current 220 ms/4096-request defaults remain explicit Alpha limits.

API reference: [Input](https://docs.godotengine.org/en/stable/classes/class_input.html),
[Node application focus notifications](https://docs.godotengine.org/en/stable/classes/class_node.html).
