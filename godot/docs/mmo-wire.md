# Direct MMO wire core — v3.main.5.01

This Godot client connects directly to the public Login/Game protocol v4. Storage
is owned by the server. The shared roadmap and acceptance live in `ai_research`;
this checkout lives at `~/work2/hello-kotone`.

`MmoClient` is an idle persistent Autoload. This patch does not connect the
renderer, local controller, or scenes to network state. From a consumer:

```gdscript
MmoClient.world_ready.connect(on_world_ready)
MmoClient.fault.connect(on_network_fault)
MmoClient.connect_world("127.0.0.1", 21060, "player1")
```

The client automatically performs Login -> advertised Game endpoint -> enter ->
map -> state -> READY. `initial_snapshot`, `last_snapshot`, `map_document`,
`player_id` and `session_id` expose confirmed handshake data. Read-only
`request_state()` / `request_map()` and `logout()` return false when busy.
`disconnect_world()` explicitly cancels the connection without promising a flush.
No connection or request is automatically retried. A public connection is closed
after 4096 requests; reconnection policy belongs to a later patch.

Signals: `state_changed`, `world_ready`, `response_received`, `event_received`,
`fault`, `disconnected`. Login success does not expose its ticket via a signal.
Faults contain a bounded local code, operation and `outcome_unknown`; server
messages/raw frames and credentials are not logged. A validated rejection has a
known outcome; losing a login/enter/logout response has an unknown outcome.

The core uses non-blocking StreamPeerTCP partial reads/writes, asynchronous DNS,
one pending request, one scheduled request, a 75 ms request interval and 16 KiB
read budget per frame. Limits: 65536 bytes including LF, connect/write 5 seconds,
request 20 seconds, partial-frame assembly 10 seconds without extending the
deadline for each arriving byte. Tests can shorten these timeouts.

The strict parser rejects duplicate keys, trailing commas, invalid UTF-8/scalars,
fraction/exponent numbers, unsafe integers, depth >16, raw CR anywhere, CRLF and BOM. Successful
public responses and event schemas are validated before dispatch; map schema 1
uses a canonical SHA-256 hash and must match the snapshot reference. Bootstrap
version errors are recognized without silently downgrading the protocol. Failure
responses require a known wire code, the correct rejected/error status and a legal
public operation for that rejection. FLUSH_FAILED requires correlated logout;
UNSUPPORTED_VERSION is accepted only via the bootstrap envelope. Invalid replies
leave a pending mutation's outcome unknown.

Events are delivered separately from request correlation. Patch 03 will implement
the world replica and epoch/revision event reduction. Disk cache and world/map
rendering belong to patch 04. A READY connection without further requests will
eventually hit the server's authenticated idle timeout; heartbeat/recovery policy
is deferred to patch 08.

## Checks

From `hello-kotone` (Godot 4.x executable on PATH):

```sh
godot --headless --path godot --script res://tests/mmo/protocol_check.gd
```

Against an already running shared server stand:

```sh
godot --headless --path godot --script res://tests/mmo/wire_check.gd -- port=21060 events=true
```

From `ai_research`, run the complete repeatable check. It creates an isolated
temporary server stand, starts real Storage/Login/Game, launches the actual Godot
client scripts and stops its own processes. Python is only test orchestration;
there is no proxy between Godot and the real services.

```sh
python3 v3/game/op/check-client-wire.py --project ../hello-kotone/godot
```

The check covers login/enter/map/state/logout, rejection, duplicate ownership,
event multiplexing, DNS and deterministic fixture faults (fragmented/coalesced
frames, malformed/oversized frames, EOF, version/correlation errors, timeout and
lost mutation replies without replay). Fixtures are only negative test endpoints.
Runtime/evidence is written to a printed temporary directory; the summary contains
the commits and source hashes of the tested client files, without keys/tickets.
For final acceptance, use `--require-committed` on clean checkouts of both repos.
The report records the exact tested commit pair and rejects changes during the run.

API reference: [StreamPeer partial IO](https://docs.godotengine.org/en/stable/classes/class_streampeer.html).
