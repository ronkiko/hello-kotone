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
	check(Contract.visual_origin_offset() == Vector2i(-128, -236), "visual origin maps pivot to root")
	check(int(value.anchor.baseline_y_px) == 236, "baseline is fixed")
	check(Contract.canonical_pixels_per_cm() == 1, "raster v1 projects one centimeter to one pixel")
	check(value.validation.allow_state_specific_scale == false, "state-specific scale forbidden")

	check(Contract.physical_height_cm("kotone") == 172, "Kotone physical height is 172 cm")
	check(Contract.physical_height_cm("yuna") == 155, "Yuna physical height is 155 cm")
	check(Contract.canonical_height_px("kotone") == 172, "Kotone canonical raster height is 172 px")
	check(Contract.canonical_height_px("yuna") == 155, "Yuna canonical raster height is 155 px")
	check(Contract.physical_height_cm("unknown") == 0, "unknown model has no implicit physical height")
	check(Contract.canonical_height_px("unknown") == 0, "unknown model has no pixel-height fallback")

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
	bad.metric_projection.canonical_pixels_per_cm = 2
	check(not Contract.validate(bad), "raster v1 projection cannot silently change")
	bad = value.duplicate(true)
	bad.validation.allow_state_specific_scale = true
	check(not Contract.validate(bad), "per-state scaling contract rejected")
	bad = value.duplicate(true)
	bad.models.yuna.physical_height_cm = 0
	check(not Contract.validate(bad), "invalid physical model height rejected")
	bad = value.duplicate(true)
	bad.models.kotone.nominal_standing_height_px = 172
	check(not Contract.validate(bad), "obsolete pixel-height field rejected by exact contract")

	print(JSON.stringify({
		"suite": "character-sprite-frame-contract",
		"checks": checks,
		"failures": failures,
		"result": "PASS" if failures.is_empty() else "FAIL",
	}))
	quit(0 if failures.is_empty() else 1)
