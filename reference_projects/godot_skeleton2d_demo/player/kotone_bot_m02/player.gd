extends CharacterBody2D

const RUN_SPEED := 200.0
const WALK_SPEED := 92.0
const ACCELERATION := 900.0
const JUMP_VELOCITY := -400.0
const HIP_REST := Vector2(627, 545)

@onready var visual_pivot: Node2D = $VisualPivot
@onready var skeleton: Skeleton2D = $VisualPivot/Sprite2D/Skeleton2D

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
	_phase = fmod(_phase + delta * 1.6, TAU)
	var breath := sin(_phase)
	_set_position("Hip", HIP_REST + Vector2(0, -2.0 * breath), delta)
	_set_rotation("Hip", 0.0, delta)
	_set_rotation("Hip/Chest", deg_to_rad(breath), delta)
	_set_rotation("Hip/Chest/Head", deg_to_rad(-0.6 * breath), delta)
	_set_rotation("Hip/Chest/RightArm", deg_to_rad(-78.0 + breath * 1.5), delta)
	_set_rotation("Hip/Chest/LeftArm", deg_to_rad(78.0 + breath * 1.5), delta)
	_set_rotation("Hip/Chest/RightArm/RightForearm", deg_to_rad(8.0), delta)
	_set_rotation("Hip/Chest/LeftArm/LeftForearm", deg_to_rad(-8.0), delta)
	_reset_legs(delta)


func _apply_grounded_gait(delta: float, speed_ratio: float) -> void:
	_phase = fmod(_phase + delta * lerpf(5.2, 7.4, speed_ratio), TAU)
	var cycle := _phase / TAU
	var right := _sample_leg(cycle)
	var left := _sample_leg(fposmod(cycle + 0.5, 1.0))
	var contact := absf(cos(_phase))
	var counter_swing := cos(_phase)
	var intensity := lerpf(0.65, 1.0, speed_ratio)

	_set_position("Hip", HIP_REST + Vector2(sin(_phase) * 2.5, contact * 7.0), delta)
	_set_rotation("Hip", deg_to_rad(sin(_phase) * 2.0 * intensity), delta)
	_set_rotation("Hip/Chest", deg_to_rad(-sin(_phase) * 3.0 * intensity), delta)
	_set_rotation("Hip/Chest/Head", deg_to_rad(sin(_phase) * 1.2 * intensity), delta)

	_set_rotation("Hip/RightLeg", deg_to_rad(right.x * intensity), delta)
	_set_rotation("Hip/RightLeg/RightLowerLeg", deg_to_rad(right.y * intensity), delta)
	_set_rotation("Hip/RightLeg/RightLowerLeg/RightFoot", deg_to_rad(-(right.x + right.y) * intensity), delta)
	_set_rotation("Hip/LeftLeg", deg_to_rad(left.x * intensity), delta)
	# Both knees flex toward the current travel direction. The whole visual is
	# mirrored for leftward travel, so the anatomical flexion reverses with it.
	_set_rotation("Hip/LeftLeg/LeftLowerLeg", deg_to_rad(left.y * intensity), delta)
	_set_rotation("Hip/LeftLeg/LeftLowerLeg/LeftFoot", deg_to_rad(-(left.x + left.y) * intensity), delta)

	_set_rotation("Hip/Chest/RightArm", deg_to_rad(-78.0 + counter_swing * 14.0 * intensity), delta)
	_set_rotation("Hip/Chest/LeftArm", deg_to_rad(78.0 + counter_swing * 14.0 * intensity), delta)
	_set_rotation("Hip/Chest/RightArm/RightForearm", deg_to_rad(8.0 + maxf(0.0, -counter_swing) * 8.0), delta)
	_set_rotation("Hip/Chest/LeftArm/LeftForearm", deg_to_rad(-8.0 - maxf(0.0, counter_swing) * 8.0), delta)


func _sample_leg(cycle: float) -> Vector2:
	# Contact -> mid-stance -> toe-off -> bent-knee swing -> contact.
	if cycle < 0.25:
		var contact_t := smoothstep(0.0, 0.25, cycle)
		return Vector2(lerpf(-6.0, 0.0, contact_t), 0.0)
	if cycle < 0.5:
		var stance_t := smoothstep(0.25, 0.5, cycle)
		return Vector2(lerpf(0.0, 8.0, stance_t), 0.0)
	if cycle < 0.75:
		var lift_t := smoothstep(0.5, 0.75, cycle)
		return Vector2(lerpf(8.0, -14.0, lift_t), lerpf(0.0, 24.0, lift_t))
	var landing_t := smoothstep(0.75, 1.0, cycle)
	return Vector2(lerpf(-14.0, -6.0, landing_t), lerpf(24.0, 0.0, landing_t))


func _apply_air_pose(delta: float) -> void:
	_set_position("Hip", HIP_REST + Vector2(0, 3), delta)
	_set_rotation("Hip/Chest/RightArm", deg_to_rad(-105.0), delta)
	_set_rotation("Hip/Chest/LeftArm", deg_to_rad(105.0), delta)
	_set_rotation("Hip/RightLeg", deg_to_rad(-8.0), delta)
	_set_rotation("Hip/RightLeg/RightLowerLeg", deg_to_rad(20.0), delta)
	_set_rotation("Hip/LeftLeg", deg_to_rad(7.0), delta)
	_set_rotation("Hip/LeftLeg/LeftLowerLeg", deg_to_rad(16.0), delta)


func _reset_legs(delta: float) -> void:
	for path in [
		"Hip/RightLeg", "Hip/RightLeg/RightLowerLeg", "Hip/RightLeg/RightLowerLeg/RightFoot",
		"Hip/LeftLeg", "Hip/LeftLeg/LeftLowerLeg", "Hip/LeftLeg/LeftLowerLeg/LeftFoot",
	]:
		_set_rotation(path, 0.0, delta)


func _set_rotation(path: String, target: float, delta: float) -> void:
	var bone := skeleton.get_node(path) as Bone2D
	bone.rotation = lerp_angle(bone.rotation, target, 1.0 - exp(-14.0 * delta))


func _set_position(path: String, target: Vector2, delta: float) -> void:
	var bone := skeleton.get_node(path) as Bone2D
	bone.position = bone.position.lerp(target, 1.0 - exp(-14.0 * delta))
