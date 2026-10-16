# 10.02 — isolated Godot SDK smoke

This project verifies the GDScript addon at repository-root `addons/mmo_sdk`.
It never opens `godot/project.godot`, starts a server or connects a socket.
The addon architecture is explained in [its README](../../addons/mmo_sdk/README.md).

Use the installed Godot binary:

```bash
GODOT_BIN=/home/user/.local/bin/godot bash experiments/client_sdk/check.sh
```

Only Godot and Python 3 are required. The runner copies the addon and project to
a temporary directory, uses the engine's normal `--import`, and runs a SceneTree
script on three fresh projects. Each must exit 0 and print the runtime PASS marker.
It checks independent clients, native HTTPRequest/WebSocketPeer types and idle
states, seven signed int64 nonces, detached results, close/idempotency, tree
removal and absence of orphan nodes. Wrong API version, wrong nonce and a missing
addon must fail. Every process has a timeout; temporary caches/projects are removed.

This replaces the retired `experiments/gnc_health` Go/C++ experiment by direct
Director instruction. **It does not prove a Go GNC ABI, server health, external
networking or production gameplay.** The 10.02 task/evidence records this changed
criterion and the installed engine revision; 10.03 remains unstarted.
