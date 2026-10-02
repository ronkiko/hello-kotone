extends RefCounted
## Shared presentation timing: public World cadence, map scale and actual distance.
const IDLE = preload("res://assets/kotone_v2_idle_front.png")
const WALK_LEFT = preload("res://assets/kotone_v2_walking_left.png")
const WALK_RIGHT = preload("res://assets/kotone_v2_walking_right.png")
const CATCH_UP_RATIO := 1.10
# Art stride in displayed metres; independent of request timing and map units.
const WALK_CYCLE_METERS := 4.0
var speed := 0.0
var cycle_pixels := 0.0
var walk_distance := 0.0
var idle_elapsed := 0.0
var animation := 0

func configure(step_units: int, interval_ms: int, units_per_meter: int, pixels_per_meter: float) -> void:
	var step_pixels := float(step_units) / float(units_per_meter) * pixels_per_meter
	speed = step_pixels * 1000.0 / float(interval_ms) * CATCH_UP_RATIO
	cycle_pixels = WALK_CYCLE_METERS * pixels_per_meter

func reset() -> void:
	walk_distance = 0.0
	idle_elapsed = 0.0
	animation = 2 # Force texture reset after a fresh baseline.

func animate(sprite: Sprite2D, before: float, after: float, target: float, delta: float) -> void:
	var distance := absf(after - before)
	# Arrival is idle immediately; no timed walking after the body stops.
	var direction := 0 if is_equal_approx(after, target) else (-1 if target < after else 1)
	if direction != animation:
		animation = direction
		idle_elapsed = 0.0
		sprite.texture = IDLE if direction == 0 else (WALK_LEFT if direction < 0 else WALK_RIGHT)
	walk_distance = fmod(walk_distance + distance, cycle_pixels)
	if direction == 0:
		idle_elapsed += delta
		sprite.frame = int(idle_elapsed / 0.3) % sprite.hframes
	else:
		sprite.frame = int(walk_distance / cycle_pixels * sprite.hframes) % sprite.hframes
