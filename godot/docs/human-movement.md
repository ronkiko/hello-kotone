# Human authoritative movement — v3.main.5.05

In MMO World, hold A/D (physical keys, with logical-key fallback) or left/right
arrows. Opposing directions cancel. Release keys after entry, Refresh, focus loss
or a known rejection before starting again. The old standalone local controller
remains detached from the MMO Kotone instance.

InputAdapter samples the current key state; it owns no position, saved steps or
request queue. MmoClient.move accepts only left/right, only in READY and only
when its one scheduled/pending request slot is empty. It enters MOVING until a
receipt or a known nonterminal rejection. Validated `world_rules` arrives before READY and supplies authoritative
movement cadence. Pacing waits that interval after the receipt; no Game interval
is hardcoded in the client. Rules are world-level and independent of zone/map. Network request spacing still applies.
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
left/right textures per frame, and follows with Camera2D. Patch 5.06 supplies one
speculative display target after an accepted local intention; see
[prediction/reconciliation](prediction-reconciliation.md).
Sprite2D edits cannot change that target, replica or a future
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

Prediction/reconciliation is implemented in patch 06, remote characters 07 and recovery/heartbeat
08. Configurable movement pacing and long-session request-budget handling are
recorded with triggers and acceptance in the shared permanent future obligations;
the current 4096-request limit remain explicit Alpha limits.

API reference: [Input](https://docs.godotengine.org/en/stable/classes/class_input.html),
[Node application focus notifications](https://docs.godotengine.org/en/stable/classes/class_node.html).

## Presentation timing corrective

Local and remote render speed comes from public movement step/cadence and map
units_per_meter: step_units / units_per_meter * pixels_per_meter * 1000 /
min_move_interval_ms. A bounded 10% catch-up margin gives 44 px/s with the current
1-unit / 200-ms world and 8 px/metre. It is presentation only; confirmed positions,
request cadence, one-step prediction and receipts remain authoritative as before.
Walk frames follow actual visual distance over an art stride of four displayed
metres. Arrival freezes the last side-facing walk frame; target gaps never flash the
front-facing idle strip. Stationary legs do not cycle. Fresh enter resets the pose.
Suspension freezes both motion and animation; a fresh baseline resets phase.

The floor now carries an absolute server-X ruler. Minor marks represent coordinate
steps at normal scale; numbered major marks and the gold confirmed-X cell/tag make
position readable. Dense map scales use bounded visible multiples. The marker
follows confirmed replica X, independently of predicted/interpolated sprite X.


## Local trajectory / gait separation corrective

Presentation no longer treats every server step as an independent walk animation.
The motion stack is split into three responsibilities:

- `PlayerMotion` is a pure World/map motion profile. One normal step uses exact
  negotiated cadence; extra 25% speed is available only after renderer lag exceeds
  one full step.
- `LocalTrajectory` owns render X and the bounded display target. It never writes
  WorldReplica or prediction and never extends the existing one-step speculative
  envelope.
- `GaitAnimator` owns facing/walk/front-idle sprites. Walk phase follows actual
  rendered distance. A held local locomotion intent can keep the last side pose
  while waiting at the speculative boundary without cycling stationary legs.
  Release plus completed reconciliation has an exact meaning and returns to
  front-facing idle without a timeout heuristic.

`MoveInput` now exposes the current held/released locomotion intent separately
from move admission. It still queues no steps and sends only direction requests.
Remote players keep confirmed-target interpolation for Alpha, but use the same
motion profile and gait animator; buffered remote timelines remain a future review.
