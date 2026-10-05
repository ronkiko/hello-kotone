extends SceneTree
## Machine-checkable Character Sprite Frame Contract v1.
const Contract = preload("res://scripts/presentation/character_sprite_frame_contract.gd")

var checks := 0
var failures := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var value := Contract.load_contract()
	check(not value.is_empty(), "manifest loads and validates")
	check(Contract.frame_size() == Vector2i(256, 256), "canonical frame is 256x256")
	check(Contract.pivot() == Vector2i(128, 236), "canonical pivot is ground contact center")
	check(int(value.anchor.baseline_y_px) == 236, "baseline is fixed")
	check(value.validation.allow_state_specific_scale == false, "state-specific scale forbidden")
	check(Contract.nominal_height("kotone") == 192, "Kotone nominal presentation height")
	check(Contract.nominal_height("yuna") == 176, "Yuna nominal presentation height")
	check(Contract.nominal_height("unknown") == 0, "unknown model has no implicit height fallback")

	var image := Image.create(256 * 3, 256 * 2, false, Image.FORMAT_RGBA8)
	check(Contract.sheet_geometry_matches(image, 3, 2), "canonical sheet geometry accepted")
	check(not Contract.sheet_geometry_matches(image, 2, 2), "wrong declared grid rejected")

	var bad := value.duplicate(true)
	bad.frame.width_px = 128
	check(not Contract.validate(bad), "128px frame rejected")
	bad = value.duplicate(true)
	bad.anchor.pivot_y_px = 255
	check(not Contract.validate(bad), "bottom-edge pivot rejected")
	bad = value.duplicate(true)
	bad.validation.allow_state_specific_scale = true
	check(not Contract.validate(bad), "per-state scaling contract rejected")
	bad = value.duplicate(true)
	bad.models.yuna.nominal_standing_height_px = 0
	check(not Contract.validate(bad), "invalid model height rejected")

	print(JSON.stringify({
		"suite": "character-sprite-frame-contract",
		"checks": checks,
		"failures": failures,
		"result": "PASS" if failures.is_empty() else "FAIL",
	}))
	quit(0 if failures.is_empty() else 1)
