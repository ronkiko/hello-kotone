# Motion wire v8 (8.05)

Login/Lobby identity and TLS contracts are unchanged; all endpoints require v8.
Game sends control_set {control_seq, drive, facing}; desired complete state is
coalesced in one slot, monotonic sequence is allocated on enqueue, requests are
spaced at least 50 ms. Unknown outcomes are never replayed after fresh enter.

Input is sampled in native _physics_process at 60 Hz. Facing changes on press;
drive engages after 100 ms and release/focus loss sets drive=0.

The reducer accepts authoritative motion_frame full zone samples (20 Hz), scoped
by epoch, zone, generation and monotonic frame_seq. Physics revisions may skip;
reliable lifecycle facts cannot alter a motion sample's identity. ACK means control
acceptance only. Node2D + AnimatedSprite2D show confirmed position/velocity/facing.
Owner prediction and remote timeline are subsequent 8.06/8.07 work.

Official primitives reviewed:
https://docs.godotengine.org/en/stable/tutorials/scripting/idle_and_physics_processing.html
https://docs.godotengine.org/en/stable/classes/class_animatedsprite2d.html
