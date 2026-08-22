extends CharacterBody2D

const RUN_SPEED := 200.0
const WALK_SPEED := 92.0
const ACCELERATION := 900.0
const JUMP_VELOCITY := -400.0
const HIP_REST := Vector2(627, 545)
const ARM_SWING_DEGREES := 24.0
const LEG_SWING_DEGREES := 12.0

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
	_update_human_pose(delta)


func _update_human_pose(delta: float) -> void:
	if not is_on_floor():
		_apply_air_pose(delta)
		return

	var speed_ratio := absf(velocity.x) / RUN_SPEED
	if speed_ratio < 0.03:
		_apply_idle_pose(delta)
	else:
		_apply_locomotion_pose(delta, speed_ratio)


func _apply_idle_pose(delta: float) -> void:
	_phase = fmod(_phase + delta * 1.8, TAU)
	var breath := sin(_phase)
	_set_position("Hip", HIP_REST + Vector2(0, -2.0 * breath), delta)
	_set_rotation("Hip", 0.0, delta)
	_set_rotation("Hip/Chest", deg_to_rad(1.2 * breath), delta)
	_set_rotation("Hip/Chest/Head", deg_to_rad(-0.8 * breath), delta)
	_set_rotation("Hip/Chest/RightArm", deg_to_rad(-78.0 + 3.0 * breath), delta)
	_set_rotation("Hip/Chest/LeftArm", deg_to_rad(78.0 + 3.0 * breath), delta)
	_reset_distal_joints(delta)
	_reset_legs(delta)


func _apply_locomotion_pose(delta: float, speed_ratio: float) -> void:
	var cadence := lerpf(5.6, 8.4, speed_ratio)
	_phase = fmod(_phase + delta * cadence, TAU)
	var stride := sin(_phase)
	var double_support := absf(cos(_phase))
	var intensity := lerpf(0.55, 1.0, speed_ratio)

	# M01 motion proof: whole arms and whole legs behave as rigid articulated
	# regions. Elbows, knees, wrists and ankles stay locked until M02 provides
	# joint art that can bend without collapsing. The deliberately visible range
	# proves that the six meshes follow the four limb roots in the live level.
	_set_position("Hip", HIP_REST + Vector2(stride * 3.0, double_support * 12.0), delta)
	_set_rotation("Hip", deg_to_rad(stride * 2.5 * intensity), delta)
	_set_rotation("Hip/Chest", deg_to_rad(-stride * 4.0 * intensity), delta)
	_set_rotation("Hip/Chest/Head", deg_to_rad(stride * 2.0 * intensity), delta)

	_set_rotation("Hip/Chest/RightArm", deg_to_rad(-78.0 + stride * ARM_SWING_DEGREES * intensity), delta)
	_set_rotation("Hip/Chest/LeftArm", deg_to_rad(78.0 + stride * ARM_SWING_DEGREES * intensity), delta)
	_set_rotation("Hip/RightLeg", deg_to_rad(stride * LEG_SWING_DEGREES * intensity), delta)
	_set_rotation("Hip/LeftLeg", deg_to_rad(-stride * LEG_SWING_DEGREES * intensity), delta)
	_reset_distal_joints(delta)


func _apply_air_pose(delta: float) -> void:
	_set_position("Hip", HIP_REST + Vector2(0, 4), delta)
	_set_rotation("Hip", 0.0, delta)
	_set_rotation("Hip/Chest", deg_to_rad(-4.0), delta)
	_set_rotation("Hip/Chest/Head", deg_to_rad(2.0), delta)
	_set_rotation("Hip/Chest/RightArm", deg_to_rad(-118.0), delta)
	_set_rotation("Hip/Chest/LeftArm", deg_to_rad(118.0), delta)
	_set_rotation("Hip/RightLeg", deg_to_rad(10.0), delta)
	_set_rotation("Hip/LeftLeg", deg_to_rad(-10.0), delta)
	_reset_distal_joints(delta)


func _reset_legs(delta: float) -> void:
	_set_rotation("Hip/RightLeg", 0.0, delta)
	_set_rotation("Hip/LeftLeg", 0.0, delta)


func _reset_distal_joints(delta: float) -> void:
	_set_rotation("Hip/Chest/RightArm/RightForearm", 0.0, delta)
	_set_rotation("Hip/Chest/LeftArm/LeftForearm", 0.0, delta)
	_set_rotation("Hip/Chest/RightArm/RightForearm/RightHand", 0.0, delta)
	_set_rotation("Hip/Chest/LeftArm/LeftForearm/LeftHand", 0.0, delta)
	_set_rotation("Hip/RightLeg/RightLowerLeg", 0.0, delta)
	_set_rotation("Hip/LeftLeg/LeftLowerLeg", 0.0, delta)
	_set_rotation("Hip/RightLeg/RightLowerLeg/RightFoot", 0.0, delta)
	_set_rotation("Hip/LeftLeg/LeftLowerLeg/LeftFoot", 0.0, delta)


func _set_rotation(path: String, target: float, delta: float) -> void:
	var bone := skeleton.get_node(path) as Bone2D
	bone.rotation = lerp_angle(bone.rotation, target, 1.0 - exp(-12.0 * delta))


func _set_position(path: String, target: Vector2, delta: float) -> void:
	var bone := skeleton.get_node(path) as Bone2D
	bone.position = bone.position.lerp(target, 1.0 - exp(-12.0 * delta))
