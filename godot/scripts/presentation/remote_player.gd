extends Node2D
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const MotionTimeline = preload("res://scripts/presentation/remote_motion_timeline.gd")

var player_id := ""
var sprite := AnimatedSprite2D.new()
var visual_layer := Node2D.new()
var identity := Label.new()
var timeline := MotionTimeline.new()
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
	identity.position.x = -64
	identity.size = Vector2(128, 18)
	identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity.add_theme_font_size_override("font_size", 11)
	add_child(identity)

func project(player: Dictionary, confirmed_pixel: float, scope: String, received_usec: int,
		top_speed_mm_s: int) -> void:
	var motion: Dictionary = player.motion.duplicate(true)
	motion["contacts"] = player.get("contacts", []).duplicate()
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
	identity.position.y = -Appearance.display_height_px(payload.character_model_id) - 18
	if update_result in ["seeded", "reset"]:
		_apply_pose(motion)

func render_at(pixel_x: float, motion: Dictionary) -> void:
	position.x = pixel_x
	_apply_pose(motion)

func set_suspended(value: bool) -> void:
	suspended = value
	if value:
		timeline.reset()
		last_motion_sample_received_usec = -1
		sprite.pause()

func timeline_metrics() -> Dictionary:
	return timeline.metrics()

func _apply_pose(motion: Dictionary) -> void:
	var animation := ("walk_" if int(motion.get("velocity_mm_s", 0)) != 0 else "idle_") \
		+ ("left" if int(motion.get("facing", 1)) < 0 else "right")
	if suspended:
		sprite.pause()
	elif sprite.animation != animation or not sprite.is_playing():
		sprite.play(animation)
