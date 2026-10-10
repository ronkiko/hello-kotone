extends Node2D
## Cosmetic, per-character impact damage; server motion-frame facts are authoritative.
## Never changes velocity, health, contact response or network state.
const LIFETIME := 2.0
const MAX_VISIBLE := 4
var last_impact_tick := 0
var _visible: Array[Label] = []

func reset() -> void:
	last_impact_tick = 0
	for label in _visible:
		if is_instance_valid(label):
			label.queue_free()
	_visible.clear()

func show_impact(motion: Dictionary, character_height_px: float) -> bool:
	var tick := int(motion.get("contact_response_tick", 0))
	var damage := int(motion.get("contact_damage", 0))
	var impulse := int(motion.get("contact_impact_impulse_g_mm_s", 0))
	var sources: Variant = motion.get("contact_impact_sources", [])
	if tick <= last_impact_tick or damage <= 0 or impulse <= 0 \
			or not sources is Array or sources.is_empty():
		return false
	last_impact_tick = tick
	for label in _visible.duplicate():
		if not is_instance_valid(label) or label.is_queued_for_deletion():
			_visible.erase(label)
	while _visible.size() >= MAX_VISIBLE:
		var oldest: Label = _visible.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var popup := Label.new()
	popup.name = "ImpactDamage"
	popup.text = "-%d" % damage
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.size = Vector2(72, 28)
	popup.position = Vector2(-36.0 + float(tick % 3 - 1) * 12.0,
		-clampf(character_height_px * 0.7, 36.0, 80.0))
	popup.z_index = 8
	popup.add_theme_font_size_override("font_size", 17)
	popup.add_theme_color_override("font_color", Color(1.0, 0.76, 0.3))
	popup.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.07))
	popup.add_theme_constant_override("outline_size", 4)
	add_child(popup)
	_visible.append(popup)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(popup, "position", popup.position + Vector2(0, -24), LIFETIME)
	tween.tween_property(popup, "modulate:a", 0.0, LIFETIME)
	tween.chain().tween_callback(popup.queue_free)
	return true
