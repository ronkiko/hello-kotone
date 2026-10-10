extends Node2D
## Global, presentation-only damage number renderer.
## The gameplay/presentation boundary validates and deduplicates the event.
## This node knows only the server-scored number and fixed world-space point.
const LIFETIME_SECONDS := 2.0

var display_enabled := true

func _ready() -> void:
	# One instance per World canvas, independent from all character nodes.
	top_level = true
	display_enabled = bool(ProjectSettings.get_setting("presentation/damage_numbers_enabled", true))

func reset() -> void:
	# Changing scene/session invalidates old visuals. Popup-owned Tweens are
	# automatically stopped when their owners are freed.
	for popup in get_children():
		popup.queue_free()

func render_number(amount: int, world_position: Vector2) -> bool:
	if not display_enabled or amount <= 0:
		return false
	var popup := Label.new()
	popup.name = "ImpactDamage"
	popup.text = "-%d" % amount
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.size = Vector2(72, 28)
	popup.position = world_position + Vector2(-36.0, 0.0)
	popup.z_index = 8
	popup.add_theme_font_size_override("font_size", 17)
	popup.add_theme_color_override("font_color", Color(1.0, 0.76, 0.3))
	popup.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.07))
	popup.add_theme_constant_override("outline_size", 4)
	add_child(popup)
	# Each number is independent: render immediately on receipt, then fade and
	# free after its own lifetime. No throttling, FIFO, cap or forced eviction.
	var tween := popup.create_tween().set_parallel(true)
	tween.tween_property(popup, "position", popup.position + Vector2(0, -24), LIFETIME_SECONDS)
	tween.tween_property(popup, "modulate:a", 0.0, LIFETIME_SECONDS)
	tween.chain().tween_callback(popup.queue_free)
	return true
