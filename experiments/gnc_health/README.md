# v3.main.10.02 — isolated Godot ↔ Go GNC local HEALTH

**This directory is an independent test project.** The existing MMO Godot application, Login, MmoClient and assets are untouched. It uses Godot 4.4+ GDExtension, a thin C++ wrapper in this client repo, and the Go-owned client implementation in the neighboring private `go-networking` repository.

The Go C ABI exports `gnc_abi_version` and `gnc_local_health`. GDScript calls `GncLocalHealth.new().local_health(nonce)`. It checks `nonce XOR 0x1234ABCD`, a deterministic **local self-test vector**; it does **not** claim to ping the server or to validate the game's network. The Go library is loaded inside the Godot process; no sidecar is started.

On Linux x86_64 with Go + CGO, g++, SCons, Godot 4.4+, and a separate **godot-cpp 4.4** checkout:

```bash
GODOT_CPP=/path/to/godot-cpp-4.4 bash experiments/gnc_health/build_and_test.sh
```

The script compiles Go `libgnc.so` and generated `libgnc.h`, compiles godot-cpp's standard static bindings, builds `libgnc_godot.so` linked to Go, imports the disposable Godot project and runs headless GDScript. Only a real Godot run that prints `PASS: Godot -> GDExtension -> Go GNC local HEALTH` and exits 0 counts as Godot proof. No binary is committed; `project/bin/` is generated locally.

**Evidence/status:** Go unit tests, `go vet`, C shared build and native C consumer smoke passed on Linux Go 1.23.2. **Godot native execution NOT VERIFIED here:** Godot and godot-cpp are not installed in the available execution environment. This project is an executable test recipe, not a claim of an already proven Godot connection.
