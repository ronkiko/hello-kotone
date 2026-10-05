# Direct MMO wire core — protocol v6

The Godot client connects directly to Login and Game over the public TCP/JSONL
protocol. Storage remains server-side. No Python proxy or private Game API exists in
the gameplay path.

`MmoClient` is a persistent Autoload. Connect performs:

```text
Login
 -> ticket + advertised Game endpoint
 -> session_rules
 -> enter: bind WorldSession realm identity + capabilities
 -> verified map/cache
 -> world_rules
 -> state boundary
 -> READY
```

Protocol version is 6. The public Game operations used by this client are:
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


## Realm binding — v3.main.6.07

`WorldSession` owns the active `{game_card_id, realm_id, realm_instance_id}` binding
and world capabilities separately from `WorldReplica` (current zone observation).
The successful Host `enter` binds it before any zone replica signal or map
projection. This client accepts the `hello-kotone` card with its required gameplay
capabilities; no world selector is added to Login.

Protocol v6 requires the snapshot epoch to equal the bootstrapped instance.
Network maps/world rules carry full identity and are rejected before presentation
or cache writes when they belong to another card, realm or instance. Facts, state
and input acknowledgments are fenced through the same instance epoch.
Immutable cached map bytes may be reused by a fresh bound snapshot reference.
Failure invalidates WorldSession while retaining only stale zone presentation;
explicit reconnect clears both and starts fresh Login/ticket/Host enter.
Host session_rules stays separate from Runtime/card world rules and capabilities.
The removed world_id alias is replaced by identity.realm_id. Restart all services
and Godot together when upgrading v5 to v6.


## Beta TLS transport — v3.main.7.08

The shared channel now supports `open(host, port, "internet_beta", trusted_ca)`
using StreamPeerTLS and TLSOptions.client. A null CA uses platform trust; an
explicit CA must be provisioned by the operator. The original hostname is
validated before connected/send. There is no unsafe TLS option or plaintext
fallback. DNS, TCP and TLS share the absolute connect deadline. Retain Beta mode
for all advertised Login/Lobby/Game endpoints. Explicit trusted_local_dev mode
allows plaintext only to literal loopback IPs.

This patch prepares transport security; the existing v6 application flow is
migrated to v7 account/realm/character screens in 7.09. Native TLS acceptance:
from the neighboring ai_research repository with supported Python, run
`python3 v3/game/op/check-beta-godot.py --project ../hello-kotone/godot`.
It covers all three public services, untrusted CA, hostname mismatch, no downgrade,
remote insecure rejection and explicit local TCP.
