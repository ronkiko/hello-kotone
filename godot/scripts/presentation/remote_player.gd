extends Node2D
## Presentation only: one remote identity and its last confirmed pixel target.
const Kotone = preload("res://scenes/kotone.tscn")
const MotionProfile = preload("res://scripts/presentation/player_motion.gd")
const GaitAnimator = preload("res://scripts/presentation/gait_animator.gd")
var sprite: Sprite2D
var identity := Label.new()
var suspended := false
var player_id := ""
var target_x := 0.0
var visual_x := 0.0
var _min_x := 0.0
var _max_x := 0.0
var _installed := false
var motion_profile := MotionProfile.new()
var gait := GaitAnimator.new()

func _ready() -> void:
	sprite = Kotone.instantiate()
	sprite.set_script(null)
	sprite.scale = Vector2(0.65, 0.65)
	# Stable identity tint; labels remain readable even at the same server X.
	sprite.modulate = Color.from_hsv(float(player_id.hash() & 255) / 255.0, 0.35, 1.0)
	add_child(sprite)
	identity.position = Vector2(-64, 24)
	identity.size = Vector2(128, 18)
	identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity.add_theme_font_size_override("font_size", 11)
	identity.add_theme_color_override("font_outline_color", Color.BLACK)
	identity.add_theme_constant_override("outline_size", 3)
	add_child(identity)

func configure_motion(step_units: int, interval_ms: int, units_per_meter: int, pixels_per_meter: float) -> void:
	motion_profile.configure(step_units, interval_ms, units_per_meter, pixels_per_meter)
	gait.configure(motion_profile.cycle_pixels)

func project(nickname: String, x: float, low: float, high: float) -> void:
	identity.text = nickname
	_min_x = low
	_max_x = high
	target_x = clampf(x, low, high)
	if not _installed:
		visual_x = target_x
		gait.reset(sprite)
		_installed = true
	position.x = visual_x

func _process(delta: float) -> void:
	if suspended or not _installed or sprite == null or motion_profile.nominal_speed <= 0.0:
		return
	var before := visual_x
	var gap := absf(target_x - visual_x)
	visual_x = clampf(move_toward(visual_x, target_x, motion_profile.speed_for_gap(gap) * maxf(delta, 0.0)), _min_x, _max_x)
	# Sprite/node edits cannot change the confirmed target.
	position.x = visual_x
	sprite.position = Vector2.ZERO
	# Remote input is intentionally unknown. Actual displacement drives walk;
	# confirmed arrival may idle until a future buffered remote timeline is added.
	gait.update(sprite, before, visual_x, target_x, 0, delta)
