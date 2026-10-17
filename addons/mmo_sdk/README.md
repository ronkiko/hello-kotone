# MMO Godot SDK addon

Isolated GDScript SDK, following the factory/owned-client organization of Nakama
Godot. It contains no Nakama source/protocol, Go runtime, native binding, sidecar,
autoload requirement or game integration. Active gameplay remains public v9.

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
belongs to Go Networking. Current 10.03 implements only historical fixture
opcodes and no extra header fields or JSON fallback. **Director clarification
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
