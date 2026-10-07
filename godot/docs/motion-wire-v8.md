# Motion wire v8 (8.05 / 8.08)

Login/Lobby identity and TLS contracts are unchanged; all endpoints require v8.
Game sends control_set {control_seq, drive, facing}; desired complete state is
coalesced in one slot, monotonic sequence is allocated on enqueue, requests are
spaced at least 50 ms. Unknown outcomes are never replayed after fresh enter.

Input is sampled in native _physics_process at 60 Hz. Facing changes on press;
drive engages after 100 ms and release/focus loss sets drive=0.

The reducer accepts authoritative motion_frame full zone samples (20 Hz), scoped
by epoch, zone, generation and monotonic frame_seq. Physics revisions may skip;
reliable lifecycle facts cannot alter a motion sample's identity. ACK means control
acceptance only. The owner predicts with CharacterBody2D; remote positions use the
delayed 60-Hz server timeline. Both use authoritative facing, including while
velocity is zero. Walking frames follow actual rendered displacement, not requested
drive or raw velocity alone.

Each card-owned motion-frame player sample also carries a bounded peer-contact
response fact: signed `contact_delta_velocity_mm_s`, response-time
`contact_response_facing` and `contact_response_tick`, plus peer IDs that caused
that response. A zero delta has zero/empty companion fields. The server keeps the
strongest fixed-tick peer response until the next 20-Hz publication, so a brief
collision cannot disappear between simulation and publication clocks. This is a
physical cause only; it contains no animation name or presentation state. It is not
checkpoint data and does not accept client-authored collision results.

Official primitives reviewed:
https://docs.godotengine.org/en/stable/tutorials/scripting/idle_and_physics_processing.html
https://docs.godotengine.org/en/stable/classes/class_animatedsprite2d.html
