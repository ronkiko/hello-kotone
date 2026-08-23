extends CharacterBody2D

const RUN_SPEED := 200.0
const WALK_SPEED := 92.0
const ACCELERATION := 900.0
const JUMP_VELOCITY := -400.0
const HIP_REST := Vector2(625, 575)
const UPPER_LEG_LENGTH := 200.0
const LOWER_LEG_LENGTH := 285.0

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
	_set_position("Hip", HIP_REST + Vector2(0, -breath), delta)
	_set_rotation("Hip", 0.0, delta)
	_apply_leg_ik("Hip/NearLeg", Vector3(8.0, 480.0, 0.0), delta)
	_apply_leg_ik("Hip/FarLeg", Vector3(-8.0, 478.0, 0.0), delta)
	_set_rotation("Hip/ArmFarUpper", deg_to_rad(2.0 - breath), delta)
	_set_rotation("Hip/ArmFarUpper/ArmFarLower", deg_to_rad(4.0), delta)
	_set_rotation("Hip/ArmFarUpper/ArmFarLower/ArmFarHand", deg_to_rad(-3.0), delta)
	_set_rotation("Hip/ArmNearUpper", deg_to_rad(-1.0 + breath), delta)
	_set_rotation("Hip/ArmNearUpper/ArmNearLower", deg_to_rad(5.0), delta)
	_set_rotation("Hip/ArmNearUpper/ArmNearLower/ArmNearHand", deg_to_rad(-3.0), delta)


func _apply_grounded_gait(delta: float, speed_ratio: float) -> void:
	_phase = fmod(_phase + delta * lerpf(5.0, 6.2, speed_ratio), TAU)
	var near_cycle := _phase / TAU
	var far_cycle := fposmod(near_cycle + 0.5, 1.0)
	var intensity := lerpf(0.72, 1.0, speed_ratio)
	var stride := sin(_phase)
	var near_ankle := _sample_ankle(near_cycle)
	var far_ankle := _sample_ankle(far_cycle)
	near_ankle.x *= intensity
	far_ankle.x *= intensity
	_set_position("Hip", HIP_REST + Vector2(0, absf(cos(_phase)) * 1.5), delta)
	_set_rotation("Hip", deg_to_rad(stride * 0.6 * intensity), delta)
	_apply_leg_ik("Hip/NearLeg", near_ankle, delta)
	_apply_leg_ik("Hip/FarLeg", far_ankle, delta)
	_set_rotation("Hip/ArmFarUpper", deg_to_rad(-stride * 8.0 * intensity), delta)
	_set_rotation("Hip/ArmFarUpper/ArmFarLower", deg_to_rad(5.0 + maxf(0.0, stride) * 4.0), delta)
	_set_rotation("Hip/ArmFarUpper/ArmFarLower/ArmFarHand", deg_to_rad(-3.0), delta)
	_set_rotation("Hip/ArmNearUpper", deg_to_rad(stride * 8.0 * intensity), delta)
	_set_rotation("Hip/ArmNearUpper/ArmNearLower", deg_to_rad(5.0 + maxf(0.0, -stride) * 4.0), delta)
	_set_rotation("Hip/ArmNearUpper/ArmNearLower/ArmNearHand", deg_to_rad(-3.0), delta)


func _sample_ankle(cycle: float) -> Vector3:
	# Six-frame Kotone walk contract: contact, loading, midstance, heel lift, toe-off, swing.
	var keys := [
		Vector3(60.0, 478.0, deg_to_rad(-6.0)),
		Vector3(35.0, 484.0, 0.0),
		Vector3(0.0, 484.0, 0.0),
		Vector3(-45.0, 480.0, deg_to_rad(8.0)),
		Vector3(-55.0, 465.0, deg_to_rad(10.0)),
		Vector3(5.0, 450.0, deg_to_rad(-3.0)),
	]
	var scaled := fposmod(cycle, 1.0) * keys.size()
	var index := int(floor(scaled)) % keys.size()
	var next_index := (index + 1) % keys.size()
	var blend := smoothstep(0.0, 1.0, scaled - floor(scaled))
	return keys[index].lerp(keys[next_index], blend)


func _apply_leg_ik(path: String, ankle_pose: Vector3, delta: float) -> void:
	var target := Vector2(ankle_pose.x, ankle_pose.y)
	var distance := clampf(target.length(), absf(LOWER_LEG_LENGTH - UPPER_LEG_LENGTH) + 0.25, UPPER_LEG_LENGTH + LOWER_LEG_LENGTH - 0.25)
	var knee_angle := acos(clampf(
		(distance * distance - UPPER_LEG_LENGTH * UPPER_LEG_LENGTH - LOWER_LEG_LENGTH * LOWER_LEG_LENGTH)
		/ (2.0 * UPPER_LEG_LENGTH * LOWER_LEG_LENGTH), -1.0, 1.0))
	var aim_angle := atan2(-target.x, target.y)
	var hip_offset := acos(clampf(
		(UPPER_LEG_LENGTH * UPPER_LEG_LENGTH + distance * distance - LOWER_LEG_LENGTH * LOWER_LEG_LENGTH)
		/ (2.0 * UPPER_LEG_LENGTH * distance), -1.0, 1.0))
	var hip_angle := aim_angle - hip_offset
	var lower_path := path + "/" + ("NearLower" if "NearLeg" in path else "FarLower")
	var foot_path := lower_path + "/" + ("NearFoot" if "NearLeg" in path else "FarFoot")
	_set_rotation(path, hip_angle, delta)
	_set_rotation(lower_path, knee_angle, delta)
	_set_rotation(foot_path, ankle_pose.z - hip_angle - knee_angle, delta)


func _apply_air_pose(delta: float) -> void:
	_set_position("Hip", HIP_REST + Vector2(0, 3), delta)
	_set_rotation("Hip/ArmFarUpper", deg_to_rad(14.0), delta)
	_set_rotation("Hip/ArmNearUpper", deg_to_rad(-18.0), delta)
	_set_rotation("Hip/ArmFarUpper/ArmFarLower", deg_to_rad(18.0), delta)
	_set_rotation("Hip/ArmNearUpper/ArmNearLower", deg_to_rad(24.0), delta)
	_set_rotation("Hip/NearLeg", deg_to_rad(-10.0), delta)
	_set_rotation("Hip/NearLeg/NearLower", deg_to_rad(24.0), delta)
	_set_rotation("Hip/FarLeg", deg_to_rad(8.0), delta)
	_set_rotation("Hip/FarLeg/FarLower", deg_to_rad(18.0), delta)


func _set_rotation(path: String, target: float, delta: float) -> void:
	var bone := skeleton.get_node(path) as Bone2D
	bone.rotation = lerp_angle(bone.rotation, target, 1.0 - exp(-14.0 * delta))


func _set_position(path: String, target: Vector2, delta: float) -> void:
	var bone := skeleton.get_node(path) as Bone2D
	bone.position = bone.position.lerp(target, 1.0 - exp(-14.0 * delta))
