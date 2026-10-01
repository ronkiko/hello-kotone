# Local prediction and server reconciliation — v3.main.5.06

An accepted left/right intention immediately selects one expected display step.
`LocalPrediction` is a pure RefCounted model; it has no sockets, scene ownership,
input sampling, queue or authoritative writes. World wires accepted intentions
to this model and supplies validated WorldReplica views and world rules.

The three positions stay separate:

- confirmed X belongs only to WorldReplica;
- predicted X is one bounded expected step from confirmed X, using world_rules.step_units;
- render X belongs to PlatformWorld, which interpolates toward the supplied display target.

The network payload remains direction only. Prediction does not add requests,
change pacing, or bypass the single scheduled/pending slot. During latency,
the character can visually reach the predicted step while the Position label
continues to show confirmed X. Key release or reversal does not cancel a step
already accepted for transmission and does not accumulate future steps.

Own moved facts reconcile speculation, including an unchanged or unexpected X.
Remote facts preserve the pending local prediction. `WorldReplica.local_moved`
is a reducer notification: consumers read confirmed state from the replica;
presentation never interprets raw wire messages. A matching receipt opens the
request slot without applying another step. LocalPrediction never decides
whether a receipt is valid; MmoClient retains all 5.05 validation and fencing.

OUT_OF_BOUNDS, RATE_LIMITED and WORLD_PAUSED clear speculation and interpolate
back to confirmed X, bounded by map limits. The session remains healthy; hold
does not automatically retry. Uncertain/malformed/lost/timed-out/cancelled moves
clear speculation and fence the connection, retaining only the last confirmed
facts as STALE. If moved arrived before the lost receipt, its confirmed X stays.
Explicit fresh Login/enter establishes a new baseline without old prediction.
State refresh only works on a healthy stream and never repairs missing facts.

Prediction is clamped at both map boundaries and resets on epoch/player/map
baseline changes, stale/resync, exit and failure. Resize preserves the current
display target. Manual Sprite2D edits cannot modify prediction, render storage,
replica or a future request; the next render tick restores presentation.

This remains discrete one-step anticipation. Continuous velocity/physics,
pipelined input, sequence/ack windows and speculative collision require the
separate future reviews recorded in the shared roadmap. Generic Host request
pacing is independent of world movement rules (permanent obligation 20).

## Acceptance

From ai_research:

```sh
python3 v3/game/op/check-client-prediction.py --project ../hello-kotone/godot --desktop --require-committed
```

This drives the shipped InputAdapter/World scene against delayed public protocol
fixtures: correct and unexpected facts, delayed receipts, remote interleaving,
known rejections, lost replies before/after moved, invalid receipt, cancellation,
timeout, explicit new epoch, map scale/min offsets and both walls. Audited traffic
contains directions only and no retry/repair/replay. Desktop mode saves predicted,
confirmed and rollback screenshots. Tests use isolated Godot user data.

Run the existing movement suite for real Storage/Login/Game min..max plus wire,
replica, map and shell regressions. No server or wire semantics changed in 5.06;
the committed 5.05 full server gate remains evidence for identical runtime.
