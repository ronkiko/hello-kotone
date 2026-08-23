extends CharacterBody2D

const RUN_SPEED := 200.0
const WALK_SPEED := 92.0
const ACCELERATION := 900.0
const JUMP_VELOCITY := -400.0
const HIP_REST := Vector2(625, 575)

@onready var visual_pivot: Node2D = $VisualPivot
@onready var skeleton: Skeleton2D = $VisualPivot/Sprite2D/Rig/Skeleton2D

var _phase := 0.0


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	elif Input.is_action_just_released(&"jump") and velocity.y < 0.0:
		velocity.y *= 0.6
	if not is_on_floor():
		velocity.y = minf(400.0, velocity.y + get_gravity().y * delta)

	var direction := Input.get_axis(&"move_left", &"move_right")
	var target_speed := WALK_SPEED if Input.is_action_pressed(&"walk") else RUN_SPEED
	velocity.x = move_toward(velocity.x, direction * target_speed, ACCELERATION * delta)
	if not is_zero_approx(direction):
		visual_pivot.scale.x = 1.0 if direction > 0.0 else -1.0

	move_and_slide()
	_update_pose(delta)


func _update_pose(delta: float) -> void:
	if not is_on_floor():
		_apply_air_pose(delta)
		return
	var speed_ratio := absf(velocity.x) / RUN_SPEED
	if speed_ratio < 0.03:
		_apply_idle_pose(delta)
	else:
		_apply_grounded_gait(delta, speed_ratio)


func _apply_idle_pose(delta: float) -> void:
	_phase = fmod(_phase + delta * 1.5, TAU)
	var breath := sin(_phase)
	_set_position("Hip", HIP_REST + Vector2(0, -1.5 * breath), delta)
	_set_rotation("Hip/ArmNear", deg_to_rad(1.5 * breath), delta)
	_reset_legs(delta)


func _apply_grounded_gait(delta: float, speed_ratio: float) -> void:
	_phase = fmod(_phase + delta * lerpf(5.0, 7.0, speed_ratio), TAU)
	var near_cycle := _phase / TAU
	var far_cycle := fposmod(near_cycle + 0.5, 1.0)
	var near_pose := _sample_leg(near_cycle)
	var far_pose := _sample_leg(far_cycle)
	var intensity := lerpf(0.65, 1.0, speed_ratio)
	var stride := sin(_phase)

	_set_position("Hip", HIP_REST + Vector2(0, absf(cos(_phase)) * 4.0), delta)
	_set_rotation("Hip", deg_to_rad(stride * 1.2 * intensity), delta)
	_set_rotation("Hip/NearLeg", deg_to_rad(near_pose.x * intensity), delta)
	_set_rotation("Hip/NearLeg/NearLower", deg_to_rad(near_pose.y * intensity), delta)
	_set_rotation("Hip/NearLeg/NearLower/NearFoot", deg_to_rad(-near_pose.x - near_pose.y * 0.65), delta)
	_set_rotation("Hip/FarLeg", deg_to_rad(far_pose.x * intensity), delta)
	_set_rotation("Hip/FarLeg/FarLower", deg_to_rad(far_pose.y * intensity), delta)
	_set_rotation("Hip/FarLeg/FarLower/FarFoot", deg_to_rad(-far_pose.x - far_pose.y * 0.65), delta)
	_set_rotation("Hip/ArmNear", deg_to_rad(stride * 12.0 * intensity), delta)


func _sample_leg(cycle: float) -> Vector2:
	# Side profile: contact -> stance -> toe-off -> bent-knee swing -> contact.
	if cycle < 0.25:
		var contact_t := smoothstep(0.0, 0.25, cycle)
		return Vector2(lerpf(-10.0, -2.0, contact_t), 0.0)
	if cycle < 0.5:
		var stance_t := smoothstep(0.25, 0.5, cycle)
		return Vector2(lerpf(-2.0, 10.0, stance_t), 0.0)
	if cycle < 0.75:
		var lift_t := smoothstep(0.5, 0.75, cycle)
		return Vector2(lerpf(10.0, -15.0, lift_t), lerpf(0.0, 28.0, lift_t))
	var landing_t := smoothstep(0.75, 1.0, cycle)
	return Vector2(lerpf(-15.0, -10.0, landing_t), lerpf(28.0, 0.0, landing_t))


func _apply_air_pose(delta: float) -> void:
	_set_position("Hip", HIP_REST + Vector2(0, 3), delta)
	_set_rotation("Hip/ArmNear", deg_to_rad(-18.0), delta)
	_set_rotation("Hip/NearLeg", deg_to_rad(-10.0), delta)
	_set_rotation("Hip/NearLeg/NearLower", deg_to_rad(24.0), delta)
	_set_rotation("Hip/FarLeg", deg_to_rad(8.0), delta)
	_set_rotation("Hip/FarLeg/FarLower", deg_to_rad(18.0), delta)


func _reset_legs(delta: float) -> void:
	for path in [
		"Hip/NearLeg", "Hip/NearLeg/NearLower", "Hip/NearLeg/NearLower/NearFoot",
		"Hip/FarLeg", "Hip/FarLeg/FarLower", "Hip/FarLeg/FarLower/FarFoot",
	]:
		_set_rotation(path, 0.0, delta)


func _set_rotation(path: String, target: float, delta: float) -> void:
	var bone := skeleton.get_node(path) as Bone2D
	bone.rotation = lerp_angle(bone.rotation, target, 1.0 - exp(-14.0 * delta))


func _set_position(path: String, target: Vector2, delta: float) -> void:
	var bone := skeleton.get_node(path) as Bone2D
	bone.position = bone.position.lerp(target, 1.0 - exp(-14.0 * delta))
