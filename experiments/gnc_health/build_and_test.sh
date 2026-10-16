#!/usr/bin/env bash
# Isolated Linux x86_64 proof, never launches hello-kotone/godot.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
network_repo="$(cd "$here/../../../go-networking" && pwd)"
if [ -z "$GODOT_CPP" ]; then echo "Set GODOT_CPP to godot-cpp 4.4 checkout" >&2; exit 2; fi
godot_bin="godot"
if [ -n "$GODOT_BIN" ]; then godot_bin="$GODOT_BIN"; fi
out="$here/project/bin"
for tool in go g++ scons "$godot_bin"; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 2; }
done
test -f "$network_repo/go.mod"
test -f "$GODOT_CPP/SConstruct"
mkdir -p "$out"
(cd "$network_repo" && CGO_ENABLED=1 go build -buildmode=c-shared -o "$out/libgnc.so" ./cmd/gnc_local)
scons -C "$GODOT_CPP" platform=linux target=template_debug -j4
cpp_lib="$(find "$GODOT_CPP/bin" -maxdepth 1 -type f -name 'libgodot-cpp.linux.template_debug*.a' | head -n 1)"
test -n "$cpp_lib" || { echo "Missing godot-cpp Linux debug static library" >&2; exit 2; }
g++ -std=c++17 -Wall -Wextra -fPIC -O0 -g \
    -I"$GODOT_CPP/include" -I"$GODOT_CPP/gen/include" -I"$GODOT_CPP/gdextension" -I"$out" \
    -shared "$here/src/gnc_local_health.cpp" "$here/src/register_types.cpp" \
    "$cpp_lib" -L"$out" -lgnc -Wl,-rpath,'$ORIGIN' -ldl -pthread -o "$out/libgnc_godot.so"
"$godot_bin" --headless --path "$here/project" --editor --quit
"$godot_bin" --headless --path "$here/project" --script res://native_health_test.gd
