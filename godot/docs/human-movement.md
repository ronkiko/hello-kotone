# Human movement — protocol v5 held input

MMO Kotone uses the same public authority boundary planned for future AI clients:

```text
A/D / arrows
  -> local held intent
  -> input(input_seq, left/right/stop)
  -> authoritative World cadence
  -> moved facts
  -> WorldReplica confirmed X
```

The client never sends X, pixels, render position, velocity or a physical result.

## Input state

`MoveInput` samples current keyboard state only. It owns no position and no step queue.
After a fresh World/focus change the keys must be released once before movement starts.

Press/reversal/release changes a local locomotion intent (-1/0/+1). `MmoClient`
coalesces that into the latest desired `input` state. At most one public request is
in flight; a change that happens while its predecessor is pending replaces the desired
next state instead of accumulating requests.

`input_seq` is strict +1 inside one Game session. Fresh enter starts again at 1.
Lost input ACK is outcome-unknown and is never replayed on another connection.

## Server cadence

One accepted right/left input is not one physical step. The Game remembers the held
direction and advances the World at `world_rules.movement.min_move_interval_ms`.
Release sends `stop`.

Physical truth arrives only through ordered `moved` events. A normal fact changes X.
At a map boundary or when the World deliberately holds the body, a same-X moved fact
is still authoritative reconciliation.

## Continuous local prediction

The local body does not wait for every server tick.

```text
held intent
  -> LocalTrajectory continuous model
  -> render X immediately
  -> GaitAnimator from actual rendered displacement

server moved facts
  -> WorldReplica confirmed X
  -> LocalPrediction reconciliation
  -> LocalTrajectory correction
```

Normal local speed is derived from public World cadence and map scale:

```text
step_pixels = step_units / units_per_meter * pixels_per_meter
nominal_speed = step_pixels * 1000 / min_move_interval_ms
```

The current 1-unit / 200-ms / 8-px scale therefore renders at 40 px/s. Render X,
predicted model X and confirmed server X are separate values.

A normal matching fact does not visually rewind the body. If authoritative facts
disagree, the render model is corrected and the sprite converges at bounded reconcile
speed.

A local same-X moved fact means **authoritative hold**. The client:
1. stops extending local prediction even if the key is still held;
2. rebases its model to confirmed X;
3. magnetically returns the sprite to that X;
4. waits for a changed moved fact or a newly accepted direction before prediction
   can continue.

This is the intended “server can hold the coordinate and the character comes back
like a magnet” behavior.

## Animation

Gait is driven by actual rendered displacement, not by server request timing.
Walk phase advances by travelled visual distance. When held intent is temporarily
blocked and the body is stationary, the side pose remains but legs do not cycle.
When local intent is stop and reconciliation is settled, the sprite returns to
front idle without a timeout heuristic.

Remote players use confirmed-target interpolation and the same distance-driven gait.
Buffered remote timelines remain a later scaling/polish obligation.

## Failure/recovery

Known `RATE_LIMITED` / `WORLD_PAUSED` input rejections do not invent movement.
Unknown input outcome, stream gap, wrong epoch or lost transport fences the session.
No input mutation is automatically replayed. Fresh Login -> enter snapshot establishes
the next authority baseline.

## Check

From `ai_research`:

```bash
python3 v3/game/op/check-client-movement.py --project ../hello-kotone/godot --desktop --require-committed
python3 v3/game/op/check-client-prediction.py --project ../hello-kotone/godot --desktop --require-committed
```

Manual acceptance before v3.main.5.09 must include long hold, short tap, release between
server facts, reversal, both walls, authoritative hold/magnet behavior and front idle.
