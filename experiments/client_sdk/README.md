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
It checks independent clients, native StreamPeerTCP type and idle
states, seven signed int64 nonces, detached results, close/idempotency, tree
removal and absence of orphan nodes. Wrong API version, wrong nonce and a missing
addon must fail. Every process has a timeout; temporary caches/projects are removed.

This replaces the retired `experiments/gnc_health` Go/C++ experiment by direct
Director instruction. **It does not prove a Go GNC ABI, server health, external
networking or production gameplay.** The 10.02 task/evidence records this changed
criterion and the installed engine revision; 10.03 adds a separately supervised fixture/TCP test.

Verified: installed `4.7.2.stable.official.ed1daf0bf`, Linux x86_64; all three cold imports/runs and all negative checks passed. Other platforms and exports are untested.


The 10.02 local regression remains network-free; HTTP/WebSocket placeholders were
replaced by TCP. The separate `project/wire_smoke.gd` runs only under Go Networking's
`tests/tcp_smoke.py`, which supplies the canonical golden JSON and random loopback
port in disposable projects. Run that script from `go-networking` with
`--client-root ../hello-kotone --godot /home/user/.local/bin/godot`.
It checks both codec implementations against the same original-reference fixture,
two real Godot SDK clients, 24 reconnects, bounded send queue, independent lifetime,
malformed/truncated/timeout input and actual GNS shutdown/IPC EOF disconnects.
No main game project or protected stand is opened. Exact revisions/results are
in the shared 10.03 evidence; original SoulWorker client compatibility is NOT TESTED.


Corrective 10.03 adds `project/ping_smoke.gd` to the SAME Go-owned TCP runner.
It checks extension golden bytes from the canonical JSON, two independent clients,
concurrent and sequential PING/PONG/RTT, repeated nonce rejection, pending bounds,
unknown opcode isolation, reconnect/close and pending failures at supervisor stop.
Independent malicious TCP peers exercise wrong nonce/opcode/length, unsolicited,
stale/duplicate/foreign replies, missing response, legacy response instead of PONG
and real disconnect; the script asserts no false successful completion. The local
10.02 runner remains network-free. Old evidence is historical; new corrective
results are in the shared 03-ping-corrective report/log/JSON.
