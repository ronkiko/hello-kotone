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

Remote roots keep `physics_interpolation_mode = OFF`. Godot's built-in physics
interpolation follows adjacent local physics transforms; its documentation calls
out networked multiplayer as a case where incoming samples may not align with local
physics ticks, making a network timeline a better fit. See [Godot physics
interpolation](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html)
and [advanced physics interpolation](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/advanced_physics_interpolation.html).
