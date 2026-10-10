extends Node2D
## Client-only FIFO dispatcher for authoritative impact damage telemetry.
## The event queue, visual dispatcher and individual 2-second render lifetimes
## have separate ownership. No collision/HP physics is modified here.
const LIFETIME_SECONDS := 2.0
const DEFAULT_STAGGER_SECONDS := 0.04

var display_enabled := true
var stagger_seconds := DEFAULT_STAGGER_SECONDS
var last_impact_tick := 0
var _pending: Array[Dictionary] = []
var _cooldown_seconds := 0.0
var _rendered_count := 0

func _ready() -> void:
	# Presentation coordinates are world/canvas positions captured per event,
	# not offsets that keep following the character after impact.
	top_level = true
	display_enabled = bool(ProjectSettings.get_setting("presentation/damage_numbers_enabled", true))
	stagger_seconds = clampf(float(ProjectSettings.get_setting(
		"presentation/damage_number_stagger_seconds", DEFAULT_STAGGER_SECONDS)), 0.0, 1.0)

func reset() -> void:
	# Scope changes deliberately discard old-session events and their visuals.
	_pending.clear()
	last_impact_tick = 0
	_cooldown_seconds = 0.0
	_rendered_count = 0
	for popup in get_children():
		popup.queue_free() # Each popup owns its Tween; no orphan animation.

func show_impact(motion: Dictionary, world_position: Vector2) -> bool:
	# The incoming contact fact is already scored by the server card. A repeated
	# authoritative frame must never enqueue the same damage event twice.
	if not display_enabled:
		return false
	var tick := int(motion.get("contact_response_tick", 0))
	var damage := int(motion.get("contact_damage", 0))
	var impulse := int(motion.get("contact_impact_impulse_g_mm_s", 0))
	var sources: Variant = motion.get("contact_impact_sources", [])
	if tick <= last_impact_tick or damage <= 0 or impulse <= 0 \
			or not sources is Array or sources.is_empty():
		return false
	last_impact_tick = tick
	_pending.append({"amount":damage, "world_position":world_position})
	# Render the first event immediately. Subsequent events are FIFO and
	# staggered; not a single event is evicted to make space for a new one.
	if _cooldown_seconds <= 0.0:
		_dispatch_next()
	return true

func _process(delta: float) -> void:
	_cooldown_seconds = maxf(0.0, _cooldown_seconds - maxf(delta, 0.0))
	if not _pending.is_empty() and _cooldown_seconds <= 0.0:
		_dispatch_next()

func _dispatch_next() -> void:
	if _pending.is_empty():
		return
	var event: Dictionary = _pending.pop_front()
	render_number(int(event.amount), event.world_position)
	_cooldown_seconds = stagger_seconds

func render_number(amount: int, world_position: Vector2) -> void:
	# Pure presentation: only a number and an explicit world-space point.
	# The Label owns its Tween and frees itself *after* its own 2-second life.
	var popup := Label.new()
	popup.name = "ImpactDamage"
	popup.text = "-%d" % amount
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.size = Vector2(72, 28)
	var lateral_offset := float(_rendered_count % 3 - 1) * 12.0
	popup.position = world_position + Vector2(lateral_offset - 36.0, 0.0)
	_rendered_count += 1
	popup.z_index = 8
	popup.add_theme_font_size_override("font_size", 17)
	popup.add_theme_color_override("font_color", Color(1.0, 0.76, 0.3))
	popup.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.07))
	popup.add_theme_constant_override("outline_size", 4)
	add_child(popup)
	var tween := popup.create_tween().set_parallel(true)
	tween.tween_property(popup, "position", popup.position + Vector2(0, -24), LIFETIME_SECONDS)
	tween.tween_property(popup, "modulate:a", 0.0, LIFETIME_SECONDS)
	tween.chain().tween_callback(popup.queue_free)
