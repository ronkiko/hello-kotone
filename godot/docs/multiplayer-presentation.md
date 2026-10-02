# Multiplayer presentation — v3.main.5.07

World shell still projects only the validated map plus defensive WorldReplica view.
PlatformWorld reconciles remote membership by player_id on every projection:
snapshot/joined creates an avatar, moved changes its confirmed pixel target,
left removes it from the scene immediately and queues it for deletion. An unchanged
identity keeps its node; state refresh does not duplicate avatars. A fresh epoch,
local identity or map rebuild drops the previous remote set.

Each RemotePlayer has a detached Kotone sprite, stable identity tint and nickname
label. It moves toward confirmed targets using the negotiated World motion profile.
Distance drives gait phase. Between facts it freezes the last side pose because
remote release intent is unknown; it never cycles the legs while stationary. There are no remote InputAdapters, sockets, request queues,
prediction or physics controllers. External node/sprite X edits are restored from
the private render position on the next tick. Replica facts remain unchanged.
Remote movement never changes the local camera or speculative target. Only local
Kotone has input and prediction; its label includes `(you)`.

Projection validates membership before allocating/removing nodes. At most 128
online players are accepted by the current public contract, including local;
normal replica views therefore create at most 127 remote avatars. Min offsets,
units_per_meter and map bounds use the same projection as local Kotone. Stale
replica data means last confirmed facts, not continuing remote simulation;
the current World shell returns to Login on connection failure.

This is target interpolation for the discrete Alpha world. Before continuous/high
frequency movement, measured jitter requirements, discontinuous teleport/transfer
or larger populations, review remote timeline buffering and bounded catch-up.
That trigger and acceptance are recorded in ai_research's permanent obligations,
item 21. No remote prediction or interpolation delay is introduced here.

## Play with two windows

From ai_research, initialize once and run an isolated shared stand:

```sh
./v3/game/op/stand.sh init client07 --profile shared
./v3/game/op/stand.sh run client07
```

Open two instances of this project (two terminal commands also work):

```sh
/home/user/.local/bin/godot --path /home/user/work2/hello-kotone/godot
```

Connect one as player1 and the other as player2 to 127.0.0.1:21060. Both start
in apartment on a fresh shared stand. Existing saved zones are retained: use
this new stand for the shared scenario. Focus a window and release/repress A/D
or arrows to move; the other window displays the confirmed movement. Move them
apart to see both sprites. Leave world removes that avatar in the other window.
Connect again to restore the checkpoint and reappear. Refresh world preserves
the current membership without duplicate nodes.

## Acceptance

```sh
python3 v3/game/op/check-client-multiplayer.py --project ../hello-kotone/godot --desktop --require-committed
```

Python starts real Storage/Login/Game and coordinates two independent Godot
processes using test command/result files. Files carry actions and observations,
never injected world facts or a network proxy. Both clients use the shipped
MmoClient, World scene, InputAdapter, prediction, replica and renderer. Synthetic
A/D with explicit test focus/release handles the desktop's single-focus rule;
product focus behavior is unchanged. Each process has isolated XDG_DATA_HOME.

Shared profile checks snapshot and joined membership, five right/left moves from
each window, equal causal revision/epoch, both displays, state refresh, logout/left
and fresh enter/joined with persisted X. Zones profile proves that neither
movement nor membership leaks between apartment and street. Desktop captures
both views, left and rejoin. Pure checks cover interpolation, node reuse/removal,
prediction/camera isolation, sprite tampering, stale/new epoch, map scaling and
the 128-player population cap. Omit --desktop for headless checks.
