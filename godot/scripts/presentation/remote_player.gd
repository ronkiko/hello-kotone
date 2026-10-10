extends Node2D
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const MotionTimeline = preload("res://scripts/presentation/remote_motion_timeline.gd")
const GaitAnimator = preload("res://scripts/presentation/gait_animator.gd")
const ImpactNumber = preload("res://scripts/presentation/impact_number.gd")

var player_id := ""
var sprite := AnimatedSprite2D.new()
var visual_layer := Node2D.new()
var identity := Label.new()
var timeline := MotionTimeline.new()
var gait := GaitAnimator.new()
var impact_numbers := ImpactNumber.new()
var visual_x: float:
	get: return position.x
var target_x: float:
	get: return _target_x
var suspended := false
var last_motion_sample_received_usec := -1
var _target_x := 0.0
var _last_position_mm := 0
var _appearance_payload: Dictionary = {}

func _ready() -> void:
	visual_layer.scale = Vector2.ONE * Appearance.DISPLAY_SCALE
	add_child(visual_layer)
	visual_layer.add_child(sprite)
	impact_numbers.name = "ImpactNumbers"
	add_child(impact_numbers)
	identity.position.x = -64
	identity.size = Vector2(128, 18)
	identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity.add_theme_font_size_override("font_size", 11)
	add_child(identity)

func project(player: Dictionary, confirmed_pixel: float, scope: String, received_usec: int,
		top_speed_mm_s: int, latest_frame_sample: Dictionary = {}) -> void:
	var motion: Dictionary = player.motion.duplicate(true)
	motion["contacts"] = player.get("contacts", []).duplicate()
	for key in ["contact_delta_velocity_mm_s", "contact_response_facing", "contact_response_tick",
			"contact_response_contacts", "contact_impact_sources",
			"contact_impact_impulse_g_mm_s", "contact_damage"]:
		if latest_frame_sample.has(key):
			motion[key] = latest_frame_sample[key].duplicate(true) \
				if key in ["contact_response_contacts", "contact_impact_sources"] else latest_frame_sample[key]
	if timeline._scope != scope:
		impact_numbers.reset()
	var update_result: String = timeline.push_sample(scope, motion, received_usec, top_speed_mm_s)
	_target_x = confirmed_pixel
	if update_result != "ignored":
		if int(motion.velocity_mm_s) != 0 or (update_result != "seeded" and int(motion.position_mm) != _last_position_mm):
			last_motion_sample_received_usec = received_usec
		_last_position_mm = int(motion.position_mm)
	if update_result in ["seeded", "reset"]:
		position.x = confirmed_pixel
	identity.text = player.nickname
	var payload: Dictionary = player.character.appearance_payload
	if payload != _appearance_payload:
		Appearance.install(sprite, payload)
		_appearance_payload = payload.duplicate(true)
		gait.reset(sprite, int(motion.get("facing", 1)))
		impact_numbers.reset()
	identity.position.y = -Appearance.display_height_px(payload.character_model_id) - 18
	gait.configure(float(top_speed_mm_s) * Appearance.world_pixels_per_meter() / 1000.0)
	if update_result == "seeded":
		gait.reset(sprite, int(motion.get("facing", 1)))
	elif update_result == "reset":
		# Position barriers do not retire pending/consumed causal response facts.
		var consumed_tick := gait.last_contact_response_tick
		if not GaitAnimator.is_contact_reaction(sprite):
			gait.reset(sprite, int(motion.get("facing", 1)))
		gait.last_contact_response_tick = consumed_tick

func render_at(pixel_x: float, motion: Dictionary, delta: float) -> void:
	var before_render_x := position.x
	position.x = pixel_x
	if suspended:
		sprite.pause()
		return
	var model_id := str(_appearance_payload.get("character_model_id", ""))
	gait.try_contact_reaction(sprite, model_id, motion)
	gait.update(sprite, before_render_x, position.x, int(motion.get("facing", 1)), delta)

func set_suspended(value: bool) -> void:
	suspended = value
	if value:
		timeline.reset()
		impact_numbers.reset()
		last_motion_sample_received_usec = -1
		gait.reset(sprite, gait.facing)
		sprite.pause()

func timeline_metrics() -> Dictionary:
	return timeline.metrics()
