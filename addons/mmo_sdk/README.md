# MMO Godot SDK addon

**IMPLEMENTED / verification in isolated 10.02.** This package follows the
[SDK structure used by Nakama](https://github.com/heroiclabs/nakama-godot): a
GDScript factory creates owned client nodes using Godot's standard transport
primitives. It does not include Nakama source or speak the Nakama protocol.

## Ownership and local flow

The application adds one SDK node to its SceneTree. `create_client()` creates
and parents an independent client; that client owns one native `HTTPRequest`
child and one native `WebSocketPeer`. Construction opens no connection and
sends no request. No Go runtime, C ABI, GDExtension, SDK build or client sidecar
is involved. No autoload or editor plugin registration is needed.

```gdscript
const Sdk = preload("res://addons/mmo_sdk/mmo_sdk.gd")
var sdk = Sdk.new()
add_child(sdk)
var client = sdk.create_client()
var result = client.local_health(42)
# result.scope == "local_sdk"; this is NOT a server response.
client.close()
```

Local health checks addon API availability, returns a detached nonce receipt
and the actual native transport types/states. It fails when the client is closed
or detached. Closing cancels owned HTTP work, releases the peer, queues the HTTP
node for deletion and emits `closed` once. Removing a client from the tree closes
it; deleting the SDK releases its child clients. One client's close does not
close another client. The factory refuses creation outside the tree.

## Scope and future integration

This 10.02 foundation provides factory, local health and lifecycle only.
**It has no connect/send/remote-health API yet.** HTTP/WebSocket exchange, sessions,
endpoint configuration, codecs, timeouts, queues and async replies require the
separately approved network patch. There is no fake successful remote operation.

The addon is maintained in `hello-kotone`; Go GNS and its future canonical wire
contract belong to `go-networking`; MMO authority remains in `ai_research`.
The active game still uses its own public v9 path. This addon is tested in a
separate project and has not been installed into that game.
