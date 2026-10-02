extends RefCounted
## Sprite gait driven by actual rendered displacement plus explicit local locomotion intent.
const IDLE = preload("res://assets/kotone_v2_idle_front.png")
const WALK_LEFT = preload("res://assets/kotone_v2_walking_left.png")
const WALK_RIGHT = preload("res://assets/kotone_v2_walking_right.png")
var cycle_pixels := 1.0
var walk_distance := 0.0
var idle_elapsed := 0.0
var facing := 0
var walking := false

func configure(value: float) -> void:
	cycle_pixels = maxf(value, 0.001)

func reset(sprite: Sprite2D) -> void:
	walk_distance = 0.0
	idle_elapsed = 0.0
	facing = 0
	walking = false
	sprite.texture = IDLE
	sprite.frame = 0

func update(sprite: Sprite2D, before: float, after: float, target: float, locomotion_intent: int, delta: float) -> void:
	var distance := absf(after - before)
	if distance > 0.0001:
		facing = -1 if after < before else 1
		walking = true
		idle_elapsed = 0.0
		sprite.texture = WALK_LEFT if facing < 0 else WALK_RIGHT
		walk_distance = fmod(walk_distance + distance, cycle_pixels)
		sprite.frame = int(walk_distance / cycle_pixels * sprite.hframes) % sprite.hframes
		return

	var settled := is_equal_approx(after, target)
	# A held direction may temporarily wait at the one-step speculative boundary.
	# Keep the last side pose, but do not advance the legs while the body is still.
	if locomotion_intent != 0 or not settled:
		walking = locomotion_intent != 0
		return

	# Local release + completed reconciliation has an exact semantic meaning: idle.
	if facing != 0 or sprite.texture != IDLE:
		facing = 0
		walking = false
		idle_elapsed = 0.0
		sprite.texture = IDLE
	idle_elapsed += maxf(delta, 0.0)
	sprite.frame = int(idle_elapsed / 0.3) % sprite.hframes
