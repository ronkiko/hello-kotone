# Realm Lobby / Creator — v3.main.7.09

Run the current v7 world/Beta stand from `~/work2/ai_research`, then open this Godot
project. Account sign-in, realm selection, roster, Creator and World are actual UI
controls. Secure server uses TLS end to end; local development accepts only literal
loopback and `dev1`/`dev2`/`dev3`. Full operator instructions and authority/failure
contracts are in `ai_research/v3/game/docs/godot-realm-lobby.md`.

Leave World drains/clears held input and waits for stop/logout/save before returning
to the same roster. Back to realms destroys Lobby authority; another visit requires
fresh Login. Sign out from World waits for the same durability barrier. Credentials,
session IDs and handoff secrets are not displayed or saved. A lost create/delete
reply keeps a scoped receipt in RAM for explicit reconciliation; it is not replayed.

Appearance schema 1 maps catalog IDs to local shader/overlay presets, consistently
in Creator, local avatar and remote avatars. It has no effect on authoritative X,
movement cadence, collision or avatar scale. Unknown metadata cannot select assets
or mutate physics. Production player projection carries full card/realm/character
binding and moved facts cannot silently change it.

Repeatable current acceptance from `ai_research`:

```bash
v3/runtime/beta-venv/bin/python v3/game/op/check-client-lobby.py \
  --project ../hello-kotone/godot --desktop --require-committed
```

The runner executes ten current regression suites and two actual Godot scene
consumers against TLS services. `--unit-only` omits the service stand; omit
`--desktop` for headless integration. Earlier Series 5 network-entry scripts are
historical harnesses awaiting invariant transfer/removal at the Series 7 cleanup
acceptance, not executable acceptance of the current public flow.
