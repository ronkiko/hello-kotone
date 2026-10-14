# Motion frame freshness — v3.main.9.04

`MmoClient` owns the monotonic watchdog for frames accepted by `WorldReplica`.
Only ordinary valid `motion_frame` refreshes it, after the World has loaded.
The 64-gap healthy history uses median/p90. The initial waits are 2×/8× the
20-Hz nominal cadence. Learning adapts min_wait between 2× the measured median
and 4× nominal, with the high percentile as a jitter guard. max_wait is at least
2× min_wait and targets 8× the median, capped at 16× nominal. TCP batch
microgaps cannot train a faster clock; degraded/stalled gaps cannot raise waits.
Four ascending HUD bars decline relative to `(age-min)/(max-min)`; zero enters
Visual Stall. The first accepted ordinary frame immediately restores four green.

Visual Stall freezes actor roots, owner prediction, peer proxies, remote
interpolation, facing and camera. Network polling, UI and keepalive continue.
Current native SpriteFrames resources are temporarily replaced with a 2–4-frame
subset of the current animation, preserving anchor/root and pose context. Very
short actions remain a still frame; no whole impact/fall action is replayed.
Thaw restores the original resources and retires motion history before authority
correction. Midair Y is preserved by the same root policy, without adding jump
physics. Existing `set_suspended` is a different mode and is not used for stalls.

Stale controls and unsent slots are retired; a fresh physical press is required.
`control_set` includes mandatory `zone_generation`. A valid increasing generation
in an ordinary frame atomically resets the control namespace; delayed old frames
cannot invalidate the recovered stream. Reliable committed damage may precede
the next nominal sample in the new generation, without advancing motion scope.
State queries and leave-control scheduling are withheld during Visual Stall.

Recovery uses the same Game connection and ordinary frames. There are no
RESTART_WAIT/RUNNING client packets, recovery snapshot, RESYNC request, client
ACK or protocol-version bump. The server independently owns T0+10s. Ordinary
Game TLS transport loss clears account/Lobby/Game authority and returns to Login;
unknown mutation/save outcomes remain explicit and are not replayed.

Validation: `frame_health_check.gd` and the shared server
`v3/game/op/check-worker-handoff.py` (two native TLS clients, moving W2→W3→W2,
real PID death, T0+5s Storage save, recovery, independent sample-delivery gap,
original 10s cutoff). This does not establish configured-cap capacity or author
visual acceptance. Native node choices follow official
[AnimatedSprite2D](https://docs.godotengine.org/en/stable/classes/class_animatedsprite2d.html)
and [CanvasLayer/Control HUD semantics](https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html).
