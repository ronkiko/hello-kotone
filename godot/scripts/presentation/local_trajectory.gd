extends RefCounted
## Local presentation trajectory. It owns render X only, never server facts or prediction.
var profile: RefCounted
var visual_x := 0.0
var target_x := 0.0
var min_x := 0.0
var max_x := 0.0
var intent := 0
var installed := false

func configure(value: RefCounted, low: float, high: float) -> void:
	profile = value
	min_x = low
	max_x = high
	if installed:
		visual_x = clampf(visual_x, min_x, max_x)
		target_x = clampf(target_x, min_x, max_x)

func reset(x: float) -> void:
	visual_x = clampf(x, min_x, max_x)
	target_x = visual_x
	intent = 0
	installed = true

func retarget(x: float) -> void:
	target_x = clampf(x, min_x, max_x)

func set_intent(direction: int) -> bool:
	if direction not in [-1, 0, 1]:
		return false
	intent = direction
	return true

func advance(delta: float) -> Dictionary:
	var before := visual_x
	if not installed or profile == null:
		return {"before": before, "after": visual_x, "target": target_x, "intent": intent, "settled": true}
	var gap := absf(target_x - visual_x)
	var speed: float = profile.speed_for_gap(gap)
	visual_x = clampf(move_toward(visual_x, target_x, speed * maxf(delta, 0.0)), min_x, max_x)
	return {"before": before, "after": visual_x, "target": target_x, "intent": intent,
		"settled": is_equal_approx(visual_x, target_x)}
