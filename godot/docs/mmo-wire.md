# Direct MMO wire core — protocol v5

The Godot client connects directly to Login and Game over the public TCP/JSONL
protocol. Storage remains server-side. No Python proxy or private Game API exists in
the gameplay path.

`MmoClient` is a persistent Autoload. Connect performs:

```text
Login
 -> ticket + advertised Game endpoint
 -> session_rules
 -> enter
 -> verified map/cache
 -> world_rules
 -> state boundary
 -> READY
```

Protocol version is 5. The public Game operations used by this client are:
`session_rules`, `enter`, `ping`, `map`, `world_rules`, `state`, `input`
and `logout`. The old public one-step `move` operation does not exist.

## Movement wire contract

Human movement sends only:

```json
{"input_seq": 1, "direction": "right"}
```

where direction is `left`, `right` or `stop`.

An input response confirms that the Game installed that input state and reports the
authoritative X at that owner boundary. It is not a movement receipt. Later physical
changes arrive independently as ordered `moved` events.

The client may render continuously from held input before those facts arrive.
Predicted/render X never appears in a request.

## Request/session policy

Only one public request is pending at a time. Input changes are bounded/coalesced as
latest desired state; they are not queued step-by-step. Human input gets the free
request slot before keepalive.

`session_rules` provides request spacing, idle timeout and keepalive interval.
`world_rules` separately provides gameplay movement cadence. Host transport policy
is not a World rule.

READY idle sends read-only `ping` only when no user/request work occupies the slot.
Incoming events do not suppress keepalive.

## Stream and failure semantics

Game events do not consume request correlation. `WorldReplica` requires contiguous
revision N+1 in one epoch/zone. State on a healthy stream is an exact boundary and
cannot repair an already detected gap.

No public mutation is automatically replayed. Losing the correlated response for
`input`, `enter` or `logout` may make outcome unknown; the connection is fenced
and recovery requires a fresh Login/enter baseline.

Tickets, session IDs and input sequence state are cleared on teardown. Old transport
callbacks are fenced by connection generation.

## Parser/limits

The wire parser remains strict: LF-terminated frames, no raw CR/LF inside a frame,
65536-byte maximum including LF, bounded nesting, safe integers, strict UTF-8,
duplicate-key rejection and strict public response/event schemas.

Public connection budget remains 4096 requests for the current Alpha. Long-session
renewal is tracked separately in the shared roadmap.

## Checks

From `ai_research`:

```bash
python3 v3/game/op/check-client-wire.py --project ../hello-kotone/godot --require-committed
python3 v3/game/op/check-client-heartbeat.py --project ../hello-kotone/godot --require-committed
```
