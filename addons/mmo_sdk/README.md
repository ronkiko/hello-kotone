# MMO Godot SDK addon

Isolated GDScript SDK, following the factory/owned-client organization of Nakama
Godot. It contains no Nakama source/protocol, Go runtime, native binding, sidecar,
autoload requirement or game integration. Active gameplay remains public v9.

**10.03 corrective:** real network PING/PONG is implemented and verified alongside
the unchanged source fixtures. Technical scope PASS; Director acceptance PENDING.
The [canonical Go wire registry](https://github.com/ronkiko/go-networking/blob/main/docs/soulworker-wire-compatibility.md)
owns exact extension IDs/payload and limited collision-audit evidence.

## Ownership and message flow

The application attaches the SDK node to SceneTree; its factory parents independent
client nodes. Each owns a native `StreamPeerTCP` and incremental candidate codec.
Construction opens no socket. Local health is a detached local API/nonce receipt
with the actual TCP peer type/state; it never claims a remote server response.
The old HTTPRequest/WebSocketPeer local placeholders were replaced in 10.03.

An explicit `connect_loopback(port)` accepts only `127.0.0.1` and a valid port.
Godot `_process` polls the peer, announces connect, drains partial writes and feeds
bounded received chunks to the codec. Complete validated frames emit detached
`frame_received` dictionaries; application logic owns any future semantic handling.
The canonical [candidate wire contract](https://github.com/ronkiko/go-networking/blob/main/docs/soulworker-wire-compatibility.md)
belongs to Go Networking. 10.03 implements historical fixture opcodes and optional Hello Kotone PING/PONG and no extra header fields or JSON fallback. **Director clarification
2026-10-17:** our SDK MAY use project-specific category/opcode IDs and new
PING/PONG commands **within this same SoulWorker frame**, provided old opcodes
retain their meanings, extension IDs do not collide with a supported historical
profile, and old clients never receive unsupported extensions. No universal
new version/request ID/group header field is required or allowed.

```gdscript
const Sdk = preload("res://addons/mmo_sdk/mmo_sdk.gd")
var sdk = Sdk.new()
add_child(sdk)
var client = sdk.create_client()
client.frame_received.connect(_on_fixture_frame)
client.connect_loopback(disposable_fixture_port)
# Wait for connected; send_frame(sender, opcode, payload) queues bounded bytes.
```

`send_frame` requires a connected client, validates codec inputs and bounds queued
bytes to two maximum candidate frames. `ERR_BUSY` leaves the queue intact; no
implicit retries or mutation replay occur. At most 4095 bytes are read per process
frame; partial frame memory and decoded output per call are bounded. Two-second
fixed smoke deadlines cover connect/idle/whole-frame read and queued writes;
partial bytes do not indefinitely extend a frame deadline. These are diagnostic
bounds, not configurable production network policy.

Malformed frames, read/write errors, timeout and actual peer loss clear pending
writes, close the socket and emit `disconnected(reason)` once. Partial EOF is
reported as truncated. The client node may explicitly reconnect after disconnect;
this resets codec/peer and never replays previous commands. `close()` is permanent,
idempotent, releases the peer and emits `closed` once. Tree removal closes clients;
SDK deletion releases its children. A client's lifetime does not close another.

## Verification and limitations

[The isolated project](../../experiments/client_sdk/README.md) checks the installed
Godot runtime, local lifecycle and independent source golden vectors; the Go-owned
TCP runner copies the same JSON fixture into its temporary project and tests two
real clients, repeated connect/close, faults and supervisor shutdown/EOF.
There is no duplicate fixture catalog in this repository.

Profile: Lazarus KRSW/OnStove **candidate, exact build unverified**. Plaintext source
samples and original reference Encrypt establish reconstructed fixture bytes;
no original client ciphertext capture or original SoulWorker.exe test is claimed.
Fixture response is inert diagnostic data, not a Login/server-list decision.
MMO admission/session/Realm/State authority remains in Python; GNS remains a
transport adapter. The addon is not installed in the main `godot/` project.
10.00 and Director acceptance remain PENDING. Other platforms/exports are untested.

## Explicit network PING lifecycle

After `connected`, call `ping(nonce_bytes)` with exactly eight bytes in canonical
big-endian uint64 order. PackedByteArray represents the full unsigned range without
Godot signed-int64 truncation. There is no automatic probe or local PONG synthesis.
GNS replies only to a received extension PING from that socket.

One request can be pending per client. `ERR_BUSY` admits no second request;
`ERR_ALREADY_EXISTS` rejects a nonce already enqueued in that client's lifetime,
including failed attempts and reconnects. The bounded 256-entry replay guard then
requires a new client node (`ERR_OUT_OF_MEMORY`); no history is silently evicted.
These fixed diagnostic limits add no production config. Nonces are detached copies.
Use `ping`, as raw `send_frame` refuses PING/PONG to prevent bypassing correlation.

The SDK consumes extension responses before generic `frame_received`. Only an
exact PONG opcode with the pending eight bytes emits `pong_received(nonce,rtt_usec)`.
RTT uses monotonic time since enqueue, including local queue delay. A one-second
PING deadline expires independently of unrelated frames. Malformed/wrong/unsolicited
or stale PONG, wrong extension opcode, timeout, socket loss, close or tree removal
closes the peer and emits `ping_failed(nonce,reason)` once if a request was pending.
A duplicate PONG after completion is rejected without emitting another success.
Per-client state is retained/reset deliberately: pending/writes clear on drop,
replay history survives reconnect, and each client owns its own native socket.
Identical nonces on two clients are valid and do not share a pending call.

The Go-owned TCP runner supplies extension golden bytes as a second shared JSON,
tests real two-client PING/PONG and RTT, actual GNS shutdown/parent EOF, and malicious
TCP peers producing wrong/absent/replayed/cross-connection replies. Negative cases
must produce no success for the affected attempt. See the separate
[corrective report](https://github.com/ronkiko/ai_research/blob/main/v3/docs/roadmap/v3/main/10/03-ping-corrective-review.md).
