extends SceneTree

const SCENE_PATH := "res://scenes/mannequin/kotone_front_neutral_rig.tscn"

const CONTROLLED_PATHS := [
	"pelvis/torso/upper_arm_right",
	"pelvis/torso/upper_arm_left",
	"pelvis/torso/upper_arm_right/forearm_right",
	"pelvis/torso/upper_arm_left/forearm_left",
	"pelvis/hip_right",
	"pelvis/hip_left",
]

const LOCKED_PATHS := [
	"pelvis/hip_right/knee_right",
	"pelvis/hip_right/knee_right/ankle_right",
	"pelvis/hip_left/knee_left",
	"pelvis/hip_left/knee_left/ankle_left",
]

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_check(packed != null, "neutral rig scene loads")
	if packed == null:
		_finish()
		return
	var rig := packed.instantiate() as Node2D
	get_root().add_child(rig)
	var skeleton := rig.get_node_or_null("Skeleton2D") as Skeleton2D
	_check(skeleton != null, "Skeleton2D exists")
	if skeleton == null:
		_finish()
		return

	_reset_pose(skeleton)
	_check_locked_limbs(skeleton, "neutral")

	_bone(skeleton, "pelvis/torso/upper_arm_right").rotation = deg_to_rad(-12.0)
	_bone(skeleton, "pelvis/torso/upper_arm_left").rotation = deg_to_rad(12.0)
	_check(_bone(skeleton, "pelvis/torso/upper_arm_right/forearm_right/hand_right").global_position.y > 270.0, "anatomical-right straight arm lowers on screen")
	_check(_bone(skeleton, "pelvis/torso/upper_arm_left/forearm_left/hand_left").global_position.y > 270.0, "anatomical-left straight arm lowers on screen")
	_check_locked_limbs(skeleton, "shoulder pose")

	_reset_pose(skeleton)
	_bone(skeleton, "pelvis/torso/upper_arm_right/forearm_right").rotation = deg_to_rad(-18.0)
	_bone(skeleton, "pelvis/torso/upper_arm_left/forearm_left").rotation = deg_to_rad(18.0)
	_check(_bone(skeleton, "pelvis/torso/upper_arm_right/forearm_right/hand_right").global_position.y > 270.0, "anatomical-right forearm bends downward")
	_check(_bone(skeleton, "pelvis/torso/upper_arm_left/forearm_left/hand_left").global_position.y > 270.0, "anatomical-left forearm bends downward")
	_check_locked_limbs(skeleton, "elbow pose")

	_reset_pose(skeleton)
	_bone(skeleton, "pelvis/hip_right").rotation = deg_to_rad(4.0)
	_bone(skeleton, "pelvis/hip_left").rotation = deg_to_rad(-4.0)
	_check(_bone(skeleton, "pelvis/hip_right/knee_right/ankle_right").global_position.x < 555.0, "anatomical-right hip abducts toward viewer-left")
	_check(_bone(skeleton, "pelvis/hip_left/knee_left/ankle_left").global_position.x > 699.0, "anatomical-left hip abducts toward viewer-right")
	_check_locked_limbs(skeleton, "hip pose")

	_reset_pose(skeleton)
	_finish()

func _bone(skeleton: Skeleton2D, path: String) -> Bone2D:
	return skeleton.get_node(path) as Bone2D

func _reset_pose(skeleton: Skeleton2D) -> void:
	for path in CONTROLLED_PATHS:
		_bone(skeleton, path).rotation = 0.0
	for path in LOCKED_PATHS:
		_bone(skeleton, path).rotation = 0.0

func _check_locked_limbs(skeleton: Skeleton2D, pose_name: String) -> void:
	for path in LOCKED_PATHS:
		var bone := _bone(skeleton, path)
		_check(is_zero_approx(bone.rotation), "%s keeps %s rotation neutral" % [pose_name, path])
		_check(bone.scale.is_equal_approx(Vector2.ONE), "%s keeps %s scale at one" % [pose_name, path])

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)

func _finish() -> void:
	if failures.is_empty():
		print("FRONT ARTICULATION SPIKE GODOT VALIDATION PASSED")
		quit(0)
	else:
		printerr("VALIDATION FAILED (%d checks)" % failures.size())
		quit(1)
