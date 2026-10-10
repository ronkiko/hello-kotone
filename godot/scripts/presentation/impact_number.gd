extends Node2D
## Cosmetic, per-character impact damage; server motion-frame facts are authoritative.
## Never changes velocity, health, contact response or network state.
const LIFETIME := 2.0
const MAX_VISIBLE := 4
var last_impact_tick := 0
var _visible: Array[Label] = []

func reset() -> void:
	last_impact_tick = 0
	# Every popup owns its tween. Queueing the popup for deletion also cancels
	# its tween, including its completion callback.
	for label in _visible:
		_retire_popup(label)
	_visible.clear()

func _retire_popup(label: Label) -> void:
	if not is_instance_valid(label):
		return
	_visible.erase(label)
	if not label.is_queued_for_deletion():
		label.queue_free()

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
	# Retire the oldest popup *and its tween* before allocating a fifth label.
	# Never leave an unbound animation referencing a freed Label.
	while _visible.size() >= MAX_VISIBLE:
		_retire_popup(_visible[0])
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
	# Node.create_tween binds the animation lifetime to its popup owner.
	# A rapid impact or session reset can now safely retire the node early.
	var tween := popup.create_tween().set_parallel(true)
	tween.tween_property(popup, "position", popup.position + Vector2(0, -24), LIFETIME)
	tween.tween_property(popup, "modulate:a", 0.0, LIFETIME)
	tween.chain().tween_callback(_retire_popup.bind(popup))
	return true
