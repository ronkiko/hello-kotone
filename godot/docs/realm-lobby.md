# Godot Realm Lobby / Creator — v3.main.7.10

The human client in `~/work2/hello-kotone/godot` uses current **protocol v7**:

```text
Account Login → Realm Directory → Realm Lobby → Character Create/Select
  → one-time world_handoff → Game bootstrap → World
  → stop → logout / checkpoint flush / Registry completion → same Lobby roster
```

`Preworld` owns account/directory and the connection-bound Lobby visit. `MmoClient`
owns only the selected-character Game visit, replica and held-input scheduler.
There is no nickname Login, saved ticket, direct Game reconnect or protocol-v6
fallback in the shipped client. Login credentials are cleared after sign-in;
Lobby/Game receive only their respective one-time handoffs. Login, Lobby and Game
all use the selected transport profile. Secure server uses native certificate-
verified Godot TLS; it never retries plaintext. Local development uses only literal
loopback. The optional test CA field is for the explicitly configured localhost
TLS rehearsal; a normal Internet server uses the system trust store.

## Human operation

Start a fresh current world stand and open `godot/project.godot`:

```bash
./v3/game/op/stand.sh init godot10 --profile world --port-base 22060
./v3/game/op/stand.sh run godot10
```

Choose **Local development**, account `dev1`, `dev2` or `dev3`, address
`127.0.0.1`, Login port `22060`. Select the online Kotone realm. Unavailable,
full, closed or unsupported-card realms cannot be selected. An empty roster offers
Create character; existing rows select a stable character ID. Creator controls use
two stages: select Kotone/Yuna on a full-body stand, then Customize shows only
that model's fine semantic options. Pointer hover and keyboard focus animate the
local preview; selected buttons show explicit state. Back to models retains same-
model edits; choosing another model resets fine options to its card defaults.
Only final Create sends one complete semantic payload with `character_model_id`.
Unknown local model/content disables the stand and requires a client update.
Delete requires a confirmation dialog and current selected generation.

For Beta, use a separately provisioned `beta` stand/account as documented in
[Beta security](beta-security.md); choose **Secure server**, the account/password,
and its public Login endpoint. For the local rehearsal only, load that stand's
`tls/localhost.pem` as the test CA. Never distribute the private key.

Leave world works while input is held: it drains the in-flight input, explicitly
sends stop, then requests logout. Only confirmed gameplay flush plus trusted Registry
completion leads back to roster. The selected character must be selected again;
re-entry has fresh session/input sequence and no intention replay. Sign out account
from World uses the same save barrier before clearing account/Lobby authority.

Back to realms closes Lobby and clears selected character, roster and binding.
It shows the retained public directory; choosing a realm then requires a fresh
account sign-in because the earlier Login connection was closed. Passwords are not
retained to silently reauthenticate. This is explicit in the UI. Multi-realm
stands and crash/restart recovery are the separate 7.11 acceptance scope.

## Failure and mutation semantics

UI distinguishes Login, Lobby and Game errors and never displays server messages,
wire payloads or raw ticket/session secrets. Game unknown outcomes are explicit;
Return to realm lobby requests fresh authoritative roster without replaying input.
Registry busy/unsafe barriers continue to prevent unsafe selection/deletion.
Lobby loss revokes its visit generation before any delayed coroutine can apply.

Create/delete use a random 128-bit idempotency key independently of wire request ID.
A lost reply retains the operation and immutable payload in RAM, scoped to account,
card and realm; at most eight unresolved scopes can be retained. Fresh sign-in and
an explicit **Reconcile pending character operation** repeats that exact operation
with a fresh wire ID. No mutation is automatically retried. Confirmed receipt is
followed by fresh list/select, never treated as fresh admission authority. These
non-secret receipts are not persisted across client process exit.

## Appearance projection

Hello-kotone card observation attaches a detached `character` projection to each
production snapshot player and joined/moved player fact:

```text
{game_card_id, realm_id, character_id, display_name,
 appearance_schema_version, appearance_payload}
```

It comes from the trusted Registry admission record. It contains no account,
credentials, slot, spawn, session or physics override. Realm State still owns only
live gameplay facts; observation decoration does not alter coordinates or cadence.
Client checks complete realm/character binding before reducing or rendering it;
moved facts cannot change semantic identity. The local preset mapping is shared by
Creator, local avatar and remote avatars. Kotone and Yuna use their authored idle/walk assets. Hair colors, model-scoped hair silhouette and
soft/bright face shading are cosmetic shader/overlay effects over the existing art;
collision and authoritative movement are unchanged; texture normalization belongs only to presentation.

Historical server Alpha fixtures may still have the old four-field player shape;
this is temporary Series 7 test scaffolding, not a production admission path.
The human client requires the selected-character projection. 7.12 must migrate
remaining historical cross-repo network harnesses to current admission or remove
them after transferring their regression invariants. The old empty-appearance
fallback and Registry 1→2 converter were removed in 7.10.

## Repeatable validation

Use the patched Beta Python runtime and native Godot:

```bash
v3/runtime/beta-venv/bin/python v3/game/op/check-client-lobby.py \
  --project ../hello-kotone/godot --desktop --require-committed
V3_PYTHON="$PWD/v3/runtime/beta-venv/bin/python" ./v3/game/op/check.sh --full
```

Without `--desktop`, Godot runs headless. `--unit-only` runs current wire/reducer/
map-cache/presentation/input/prediction/heartbeat/realm and pre-world boundary checks.
The integrated runner starts real production TLS Login/Lobby/Game/Storage and two
real Godot processes. Python controls service lifecycle, not gameplay. Godot uses
actual scene controls for account/realm/creator/selection/entry/delete/logout.
Screenshots, source hashes, tested commit pair and results live under the requested
`--output` directory (default `v3/runtime/godot-lobby09`). Authored Yuna runtime assets are in the client `godot/assets/`; no asset paths enter wire or Registry.
