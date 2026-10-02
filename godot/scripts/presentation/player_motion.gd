extends RefCounted
## Pure presentation motion profile derived from public World cadence and map scale.
const MAX_CATCH_UP_RATIO := 1.25
const RECONCILE_RATIO := 4.0
const WALK_CYCLE_METERS := 4.0
var nominal_speed := 0.0
var max_speed := 0.0
var step_pixels := 0.0
var cycle_pixels := 0.0

func configure(step_units: int, interval_ms: int, units_per_meter: int, pixels_per_meter: float) -> void:
	step_pixels = float(step_units) / float(units_per_meter) * pixels_per_meter
	nominal_speed = step_pixels * 1000.0 / float(interval_ms)
	max_speed = nominal_speed * MAX_CATCH_UP_RATIO
	cycle_pixels = WALK_CYCLE_METERS * pixels_per_meter

func speed_for_gap(gap_pixels: float) -> float:
	if nominal_speed <= 0.0 or step_pixels <= 0.0:
		return 0.0
	# One normal speculative/confirmed step moves at exact World cadence.
	# Extra speed exists only when presentation is already more than one step behind.
	if gap_pixels <= step_pixels + 0.001:
		return nominal_speed
	var excess_steps := clampf((gap_pixels - step_pixels) / step_pixels, 0.0, 1.0)
	return lerpf(nominal_speed, max_speed, excess_steps)


func reconcile_speed() -> float:
	return nominal_speed * RECONCILE_RATIO
