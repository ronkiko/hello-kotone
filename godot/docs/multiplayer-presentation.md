# Current v8 baseline

8.05 replaces the discrete movement implementation described historically in Series 5.
See [Motion wire v8](motion-wire-v8.md) for the current control, reducer and confirmed
presentation contracts. Owner prediction/reconciliation is in 8.06; the remote server
timeline is in 8.07.

## Remote motion timeline

Each remote character keeps the latest eight accepted authoritative samples. The
presentation cursor follows the 60-Hz `simulation_tick` timeline 100 ms behind the
estimated latest server tick. Sample receipt time anchors local elapsed time; it does
not replace the server tick. The cursor never moves backward when a frame arrives
late. Position and velocity interpolate between matching sample ticks, and the
authoritative `facing` field selects the directional animation.

When the cursor is ahead of the newest sample, the renderer may extrapolate from
that sample's authoritative velocity for at most 100 ms and at most 250 mm. It then
freezes position and gait until an authoritative frame arrives. A reported contact
also blocks extrapolation. Client input is never used to move another character.

The timeline resets when the epoch, map or zone generation changes, when contact
membership changes, when the server tick gap exceeds 12 ticks, or when the incoming
position differs from the previous velocity-based prediction by more than 250 mm.
The last two cases cover same-zone teleports and discontinuities without adding a
client-authored movement signal. Duplicate and older ticks are ignored. A reset
starts from the new authoritative sample, so positions are never blended through a
contact transition or teleport.

## Shared facing and motion-driven gait (8.08)

The server's `facing` sample remains authoritative even when `drive=0` and
`velocity_mm_s=0`. A short directional tap can therefore update the owner's and
observer's stationary directional idle without changing position. Renderers never
derive facing from the sign of displacement.

The owner and remote avatar use the same gait cursor. `AnimatedSprite2D` selects
the prepared left/right `SpriteFrames` animation from facing and advances walk
frames from actual displayed displacement. It does not read held input to decide
whether the character walks. A server impulse can move a character with drive at
zero; a stationary body settles to its facing-specific idle.

Peer contact and a nonzero server-computed contact-induced velocity change are
published separately from ordinary contact membership. The sample retains the
response tick, facing at the response, and peer IDs through the next 20-Hz frame.
The remote timeline exposes that cause only after its delayed cursor reaches the
response tick. For the installed Yuna model, a sufficiently strong rightward push
from behind can play the prepared non-looping `stumble_back` SpriteFrames reaction (mirrored for left-facing back impacts; `stumble_front` awaits authored frames).
No animation identity crosses the wire, wall contact cannot trigger it, and the
reaction never changes body physics or position.

Remote roots keep `physics_interpolation_mode = OFF`. Godot's built-in physics
interpolation follows adjacent local physics transforms; its documentation calls
out networked multiplayer as a case where incoming samples may not align with local
physics ticks, making a network timeline a better fit. See [Godot physics
interpolation](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html)
and [advanced physics interpolation](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/advanced_physics_interpolation.html).
