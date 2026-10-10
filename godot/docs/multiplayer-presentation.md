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

A new closing peer impact produces a measured server mass/velocity contact
change with `contact_impact_sources` identifying the physically struck body;
ordinary pusher deceleration has no impact-source marker, and held contact
motor force never manufactures an impact. This replaces the prior motor-owned
knockback velocity. Contact facts are published separately from membership. The sample retains the
response tick, facing at the response, and peer IDs through the next 20-Hz frame.
The remote timeline exposes that cause only after its delayed cursor reaches the
response tick. For the installed Yuna model, a sufficiently strong server-confirmed shove
is classified relative to the receiver: impact motion matching response-time
facing is `back`, and opposing it is `front`. `back` plays the prepared
non-looping `stumble_back` frames for both world directions (presentation-only
mirroring for left-facing receivers); `stumble_front` awaits its own authored
frames and must not borrow the back reaction.
No animation identity crosses the wire, wall contact cannot trigger it, and the
reaction never changes body physics or position.

Remote roots keep `physics_interpolation_mode = OFF`. Godot's built-in physics
interpolation follows adjacent local physics transforms; its documentation calls
out networked multiplayer as a case where incoming samples may not align with local
physics ticks, making a network timeline a better fit. See [Godot physics
interpolation](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html)
and [advanced physics interpolation](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/advanced_physics_interpolation.html).


Damage display is a **standard Godot scene**, not a custom event queue.

* Server `damage_resolved` is an ordered, non-coalesced gameplay fact,
  independent of the 20-Hz `motion_frame` used for interpolation.
* `WorldReplica` validates the packet, checks its scope, target/source
  entity membership and event sequence, then emits
  `signal damage_resolved(event)`. All network/ordering logic ends there.
* The world-owned presenter `DamageEffects.tscn` subscribes through
  `PlatformWorld` and converts the server contact `position_mm` into the
  SubViewport's world coordinates. It receives only damage amount and point.
* Each call instantiates `DamageNumber.tscn` via `PackedScene.instantiate()`.
  Its `Label` and `AnimationPlayer` are edited in the Godot scene itself;
  the animation floats and fades for 2 seconds and
  `animation_finished` calls `queue_free()`. No project timers,
  `Tween`, FIFOs, per-character managers, delays or visible-count caps.
* The only config toggle is
  `[presentation] damage_numbers_enabled=true` in `project.godot`.
  Turning it off disables visuals, not server physics or damage scoring.
* `motion_frame` retains mass-aware signed contact reaction fields for
  `stumble_back` / future `stumble_front`; damage score and impulse are
  no longer in the movement packet. One physical hit can produce an
  animation cue and a separate reliable damage event.
* HP is a **future authoritative card-owned entity attribute**, not a
  visual number accumulator. A future health bar uses
  `TextureProgressBar` updated from replicated HP state/snapshots. No
  `hp -= damage` in Godot and no current HP mutation.

Transport ordering is handled by the existing Python MMO observation
connection; `MultiplayerSpawner`, `MultiplayerSynchronizer`, and Godot
RPC are *not* used because this project's server is not a Godot
MultiplayerAPI peer.
