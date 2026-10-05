extends RefCounted
## Canonical 2D character sprite-frame ABI.
##
## Physical model dimensions are stored in centimeters. Raster v1 projects
## centimeters into canonical pixels; runtime world position never depends on
## bitmap bounds or arbitrary source-sheet dimensions.

const MANIFEST_PATH := "res://assets/mmo/character_sprite_frame_contract_v1.json"

static var _cached: Dictionary = {}

static func load_contract() -> Dictionary:
	if not _cached.is_empty():
		return _cached.duplicate(true)
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	if not value is Dictionary or not validate(value):
		return {}
	_cached = value.duplicate(true)
	return _cached.duplicate(true)

static func _whole_positive(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var iv := int(value)
	return float(iv) == float(value) and iv > 0

static func validate(value: Dictionary) -> bool:
	if value.get("schema") != 1:
		return false
	var frame: Variant = value.get("frame")
	var anchor: Variant = value.get("anchor")
	var projection: Variant = value.get("metric_projection")
	var safe: Variant = value.get("safe_area")
	var validation: Variant = value.get("validation")
	var models: Variant = value.get("models")
	if not frame is Dictionary or not anchor is Dictionary or not projection is Dictionary:
		return false
	if not safe is Dictionary or not validation is Dictionary or not models is Dictionary:
		return false
	if frame.keys().size() != 2 or not frame.has("width_px") or not frame.has("height_px"):
		return false
	if anchor.keys().size() != 4 or not anchor.has("semantic") or not anchor.has("pivot_x_px") or not anchor.has("pivot_y_px") or not anchor.has("baseline_y_px"):
		return false
	if projection.keys().size() != 1 or not projection.has("canonical_pixels_per_cm"):
		return false
	if safe.keys().size() != 4 or not safe.has("left_px") or not safe.has("top_px") or not safe.has("right_px") or not safe.has("bottom_px"):
		return false
	if validation.keys().size() != 2 or not validation.has("root_drift_tolerance_px") or not validation.has("allow_state_specific_scale"):
		return false
	if frame.get("width_px") != 256 or frame.get("height_px") != 256:
		return false
	if anchor.get("semantic") != "ground_contact_center":
		return false
	if anchor.get("pivot_x_px") != 128 or anchor.get("pivot_y_px") != 236:
		return false
	if anchor.get("baseline_y_px") != 236:
		return false
	if not _whole_positive(projection.get("canonical_pixels_per_cm")):
		return false
	if int(projection.get("canonical_pixels_per_cm")) != 1:
		return false
	if safe.get("left_px") != 8 or safe.get("top_px") != 8:
		return false
	if safe.get("right_px") != 248 or safe.get("bottom_px") != 244:
		return false
	if validation.get("root_drift_tolerance_px") != 1:
		return false
	if validation.get("allow_state_specific_scale") != false:
		return false
	if models.is_empty():
		return false
	for model_id in models:
		var model: Variant = models[model_id]
		if not model is Dictionary:
			return false
		if model.keys().size() != 1 or not model.has("physical_height_cm"):
			return false
		if not _whole_positive(model.get("physical_height_cm")):
			return false
		var height_px := int(model.get("physical_height_cm")) * int(projection.get("canonical_pixels_per_cm"))
		if height_px >= int(anchor.get("baseline_y_px")):
			return false
	return true

static func frame_size() -> Vector2i:
	var value := load_contract()
	if value.is_empty():
		return Vector2i.ZERO
	return Vector2i(value.frame.width_px, value.frame.height_px)

static func pivot() -> Vector2i:
	var value := load_contract()
	if value.is_empty():
		return Vector2i.ZERO
	return Vector2i(value.anchor.pivot_x_px, value.anchor.pivot_y_px)

static func visual_origin_offset() -> Vector2i:
	return -pivot()

static func canonical_pixels_per_cm() -> int:
	var value := load_contract()
	if value.is_empty():
		return 0
	return int(value.metric_projection.canonical_pixels_per_cm)

static func physical_height_cm(character_model_id: String) -> int:
	var value := load_contract()
	if value.is_empty() or not value.models.has(character_model_id):
		return 0
	return int(value.models[character_model_id].physical_height_cm)

static func canonical_height_px(character_model_id: String) -> int:
	var height_cm := physical_height_cm(character_model_id)
	var px_per_cm := canonical_pixels_per_cm()
	if height_cm <= 0 or px_per_cm <= 0:
		return 0
	return height_cm * px_per_cm

static func sheet_geometry_matches(image: Image, columns: int, rows: int) -> bool:
	if image == null or columns <= 0 or rows <= 0:
		return false
	var size := frame_size()
	return image.get_width() == size.x * columns and image.get_height() == size.y * rows
