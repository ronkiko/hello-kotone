extends RefCounted
## Continuous local predictor/render trajectory. Server facts may shift model X; render follows magnetically.
var profile: RefCounted
var model_x := 0.0
var visual_x := 0.0
var min_x := 0.0
var max_x := 0.0
var intent := 0
var installed := false

func configure(value: RefCounted, low: float, high: float) -> void:
	profile = value
	min_x = low
	max_x = high
	if installed:
		model_x = clampf(model_x, min_x, max_x)
		visual_x = clampf(visual_x, min_x, max_x)

func reset(x: float) -> void:
	model_x = clampf(x, min_x, max_x)
	visual_x = model_x
	intent = 0
	installed = true

func set_intent(direction: int) -> bool:
	if direction not in [-1, 0, 1]:
		return false
	intent = direction
	return true

func correct_by(delta_pixels: float) -> void:
	if installed:
		model_x = clampf(model_x + delta_pixels, min_x, max_x)

func correct_to(pixel_x: float) -> void:
	if installed:
		model_x = clampf(pixel_x, min_x, max_x)

func advance(delta: float) -> Dictionary:
	var before := visual_x
	if not installed or profile == null:
		return {"before": before, "after": visual_x, "target": model_x, "intent": intent, "settled": true}
	var dt := maxf(delta, 0.0)
	var old_model := model_x
	if intent != 0:
		model_x = clampf(model_x + float(intent) * profile.nominal_speed * dt, min_x, max_x)
	var aligned_before := is_equal_approx(visual_x, old_model)
	if aligned_before:
		visual_x = model_x
	else:
		visual_x = move_toward(visual_x, model_x, profile.reconcile_speed() * dt)
	return {"before": before, "after": visual_x, "target": model_x, "intent": intent,
		"settled": is_equal_approx(visual_x, model_x)}
