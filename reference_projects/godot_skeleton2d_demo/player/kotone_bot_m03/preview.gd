extends Node2D

const UPPER_LEG_LENGTH := 200.0
const LOWER_LEG_LENGTH := 285.0
const AUTO_MODE := -1
const IDLE_MODE := 0
const WALK_MODE := 1

@onready var skeleton: Skeleton2D = $Rig/Skeleton2D
@onready var instruction: Label = $Instruction

var _elapsed := 0.0
var _gait_phase := 0.0
var _forced_mode := AUTO_MODE


func _process(delta: float) -> void:
	_elapsed += delta
	var mode := _forced_mode
	if mode == AUTO_MODE:
		mode = IDLE_MODE if fmod(_elapsed, 9.0) < 3.0 else WALK_MODE
	if mode == IDLE_MODE:
		_apply_idle(delta)
	else:
		_apply_walk(delta)
	instruction.text = "KTN-RC3-M03  %s  |  0 AUTO  1 IDLE  2 WALK" % ("IDLE" if mode == IDLE_MODE else "WALK")


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_0:
			_forced_mode = AUTO_MODE
		KEY_1:
			_forced_mode = IDLE_MODE
		KEY_2:
			_forced_mode = WALK_MODE


func _apply_idle(delta: float) -> void:
	var breath := sin(_elapsed * 1.5)
	_set_position("Hip", Vector2(625, 575 - breath), delta)
	_set_rotation("Hip", 0.0, delta)
	_apply_leg_ik("Hip/NearLeg", Vector3(8.0, 480.0, 0.0), delta)
	_apply_leg_ik("Hip/FarLeg", Vector3(-8.0, 478.0, 0.0), delta)
	var arm_breath := deg_to_rad(breath * 0.35)
	_set_rotation("Hip/ArmFarUpper", arm_breath, delta)
	_set_rotation("Hip/ArmFarUpper/ArmFarLower", deg_to_rad(2.0), delta)
	_set_rotation("Hip/ArmFarUpper/ArmFarLower/ArmFarHand", deg_to_rad(-2.0), delta)
	_set_rotation("Hip/ArmNearUpper", arm_breath, delta)
	_set_rotation("Hip/ArmNearUpper/ArmNearLower", deg_to_rad(2.0), delta)
	_set_rotation("Hip/ArmNearUpper/ArmNearLower/ArmNearHand", deg_to_rad(-2.0), delta)


func _apply_walk(delta: float) -> void:
	_gait_phase = fmod(_gait_phase + delta * 5.2, TAU)
	var near_cycle := _gait_phase / TAU
	var far_cycle := fposmod(near_cycle + 0.5, 1.0)
	var stride := sin(_gait_phase)
	_set_position("Hip", Vector2(625, 575 + absf(cos(_gait_phase)) * 1.5), delta)
	_set_rotation("Hip", deg_to_rad(stride * 0.6), delta)
	_apply_leg_ik("Hip/NearLeg", _sample_ankle(near_cycle), delta)
	_apply_leg_ik("Hip/FarLeg", _sample_ankle(far_cycle), delta)
	_set_rotation("Hip/ArmFarUpper", deg_to_rad(-stride * 8.0), delta)
	_set_rotation("Hip/ArmFarUpper/ArmFarLower", deg_to_rad(5.0 + maxf(0.0, stride) * 4.0), delta)
	_set_rotation("Hip/ArmFarUpper/ArmFarLower/ArmFarHand", deg_to_rad(-3.0), delta)
	_set_rotation("Hip/ArmNearUpper", deg_to_rad(stride * 8.0), delta)
	_set_rotation("Hip/ArmNearUpper/ArmNearLower", deg_to_rad(5.0 + maxf(0.0, -stride) * 4.0), delta)
	_set_rotation("Hip/ArmNearUpper/ArmNearLower/ArmNearHand", deg_to_rad(-3.0), delta)


func _sample_ankle(cycle: float) -> Vector3:
	# Six measured gait keys: contact, loading, midstance, heel lift, toe-off, swing.
	var keys := [
		Vector3(48.0, 480.0, deg_to_rad(-4.0)),
		Vector3(28.0, 484.0, 0.0),
		Vector3(0.0, 484.0, 0.0),
		Vector3(-30.0, 482.0, deg_to_rad(4.0)),
		Vector3(-42.0, 475.0, deg_to_rad(7.0)),
		Vector3(12.0, 468.0, deg_to_rad(-2.0)),
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


func _set_rotation(path: String, target: float, delta: float) -> void:
	var bone := skeleton.get_node(path) as Bone2D
	bone.rotation = lerp_angle(bone.rotation, target, 1.0 - exp(-14.0 * delta))


func _set_position(path: String, target: Vector2, delta: float) -> void:
	var bone := skeleton.get_node(path) as Bone2D
	bone.position = bone.position.lerp(target, 1.0 - exp(-14.0 * delta))
