# Continuous local prediction and authoritative reconciliation — protocol v5

Prediction is presentation, not authority.

The local player has three distinct positions:

- **confirmed X** — only `WorldReplica`, from Game snapshot/events;
- **model X** — local continuous trajectory derived from held input;
- **render X** — sprite position converging toward the local model.

Holding a direction advances model/render immediately at the negotiated World speed.
It is not restricted to one speculative server step and does not wait for one request
per movement tick.

## Input and reconciliation

`MmoClient` sends state transitions with strict `input_seq`. The Game advances held
input independently and publishes `moved` facts.

For an ordinary matching moved fact, `LocalPrediction` advances its authoritative
step accounting and usually returns zero correction. If actual server movement differs
from the expected path, the model is adjusted while render converges smoothly.

A same-X local moved fact has stronger meaning: the server held the body. Prediction
rebases at that confirmed X and `LocalTrajectory.authoritative_hold` prevents further
local extension while the key remains held. The sprite therefore returns magnetically
to server X instead of immediately running away again.

A later changed moved fact releases that authoritative hold. A newly accepted non-stop
direction also intentionally releases an earlier map-boundary hold. A WORLD_PAUSED
rejection does not.

## Release/reversal

Release changes local intent to stop immediately. The stop input is coalesced behind an
already pending request if necessary. Once its ACK is known, the presentation converges
to the latest confirmed X and front idle is entered only after the trajectory settles.

Reversal is another input-state transition; it does not replay old steps.

## Stream failure

Unknown input outcome, revision gap, wrong epoch or malformed correlation clears the
active prediction context and fences the connection. Old prediction/input history is
never replayed into a fresh session.

## Check

```bash
python3 v3/game/op/check-client-prediction.py --project ../hello-kotone/godot --desktop --require-committed
```

The suite covers delayed ACK with immediate local motion, matching facts, same-X
authoritative hold, release-before-ACK coalescing and lost input reply/no replay.
