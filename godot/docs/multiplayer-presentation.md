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


Impact damage numbers are a separate cosmetic presentation from gait. The
server `motion_frame` supplies `contact_impact_impulse_g_mm_s` (g·mm/s) and
`contact_damage` (game-card-scored integer), associated with
`contact_response_tick` and `contact_impact_sources`. Once a frame has
passed protocol validation, `PlatformWorld` enqueues its received damage
facts immediately from `motion_received`, **before** owner prediction or
remote interpolation can overwrite position samples.

Each character has an independent `ImpactNumber` FIFO. The dispatcher
accepts a damage amount and a frozen world-space position derived from the
server event; it renders the first number immediately and staggers subsequent
numbers by 40 ms. New events do NOT evict already rendered numbers or pending
queue entries. `render_number(amount, world_position)` owns no physics,
network or deduplication decisions. Each popup owns its own Tween and removes
itself 2 seconds after its individual render start; moving characters do not
drag old numbers along. Event ticks are deduplicated per character and scope.
Only a scene/scope reset may clear an unfinished queue and its visuals.

Project config in `godot/project.godot`:

```ini
[presentation]
damage_numbers_enabled=true
damage_number_stagger_seconds=0.04
```

Turning `damage_numbers_enabled` off suppresses this optional visual
presentation, never server-side damage or collision. No client HP mutation,
no invented impulse, no local damage formula; authoritative card score
arrives through the existing telemetry contract. Missing `stumble_front`
art cannot suppress a valid damage number.

**Wire limitation:** the 20-Hz server `motion_frame` currently coalesces
multiple contact facts between publications. This client FIFO preserves
*every accepted published damage fact*, not physical impacts that were never
delivered. A future durable HP/combat system needs ordered non-coalescing
server events; it must not rely on the visual FIFO as a lossless damage ledger.
