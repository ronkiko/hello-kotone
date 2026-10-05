extends RefCounted
## Sprite gait driven by actual rendered displacement plus explicit local locomotion intent.
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
var cycle_pixels := 1.0
var walk_distance := 0.0
var idle_elapsed := 0.0
var facing := 0
var walking := false
var idle_on_settle := true

func configure(value: float) -> void:
	cycle_pixels = maxf(value, 0.001)

func reset(sprite: AnimatedSprite2D) -> void:
	walk_distance = 0.0
	idle_elapsed = 0.0
	facing = 0
	walking = false
	Appearance.pose(sprite, false, 0, 0)

func update(sprite: AnimatedSprite2D, before: float, after: float, target: float, locomotion_intent: int, delta: float) -> void:
	var distance := absf(after - before)
	if distance > 0.0001:
		facing = -1 if after < before else 1
		walking = true
		idle_elapsed = 0.0
		walk_distance = fmod(walk_distance + distance, cycle_pixels)
		Appearance.pose(sprite, true, facing, int(walk_distance / cycle_pixels * Appearance.walk_frame_count(sprite, facing)))
		return

	var settled := is_equal_approx(after, target)
	# Held input may be temporarily blocked by authoritative World state.
	# Keep the last side pose, but do not advance the legs while the body is still.
	if locomotion_intent != 0 or not settled:
		walking = locomotion_intent != 0
		return

	if not idle_on_settle and facing != 0:
		walking = false
		return # Remote release is unknown; freeze the last side pose.

	# Local release + completed reconciliation has an exact semantic meaning: idle.
	if facing != 0 or walking:
		facing = 0
		walking = false
		idle_elapsed = 0.0
		Appearance.pose(sprite, false, 0, 0)
	idle_elapsed += maxf(delta, 0.0)
	Appearance.pose(sprite, false, 0, Appearance.idle_frame(sprite, idle_elapsed))
