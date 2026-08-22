extends SceneTree

const SCENE_PATH := "res://scenes/mannequin/kotone_front_neutral_rig.tscn"

const EXPECTED_BONES := {
	"pelvis": Vector2(627, 545),
	"pelvis/torso": Vector2(627, 430),
	"pelvis/torso/head_neck": Vector2(627, 205),
	"pelvis/torso/upper_arm_right": Vector2(552, 244),
	"pelvis/torso/upper_arm_right/forearm_right": Vector2(414, 263),
	"pelvis/torso/upper_arm_right/forearm_right/hand_right": Vector2(300, 270),
	"pelvis/torso/upper_arm_left": Vector2(702, 244),
	"pelvis/torso/upper_arm_left/forearm_left": Vector2(840, 263),
	"pelvis/torso/upper_arm_left/forearm_left/hand_left": Vector2(954, 270),
	"pelvis/hip_right": Vector2(555, 565),
	"pelvis/hip_right/knee_right": Vector2(555, 765),
	"pelvis/hip_right/knee_right/ankle_right": Vector2(555, 1040),
	"pelvis/hip_left": Vector2(699, 565),
	"pelvis/hip_left/knee_left": Vector2(699, 765),
	"pelvis/hip_left/knee_left/ankle_left": Vector2(699, 1040),
}

const EXPECTED_SPRITES := {
	"pelvis/Pelvis": {"position": Vector2(512, 405), "z": 12},
	"pelvis/torso/Torso": {"position": Vector2(511, 185), "z": 13},
	"pelvis/torso/head_neck/HeadNeck": {"position": Vector2(545, 54), "z": 14},
	"pelvis/torso/upper_arm_right/UpperArmRight": {"position": Vector2(365, 219), "z": 2},
	"pelvis/torso/upper_arm_right/forearm_right/ForearmRight": {"position": Vector2(260, 240), "z": 1},
	"pelvis/torso/upper_arm_right/forearm_right/hand_right/HandRight": {"position": Vector2(213, 251), "z": 0},
	"pelvis/torso/upper_arm_left/UpperArmLeft": {"position": Vector2(679, 219), "z": 5},
	"pelvis/torso/upper_arm_left/forearm_left/ForearmLeft": {"position": Vector2(809, 240), "z": 4},
	"pelvis/torso/upper_arm_left/forearm_left/hand_left/HandLeft": {"position": Vector2(924, 250), "z": 3},
	"pelvis/hip_right/ThighRight": {"position": Vector2(512, 520), "z": 8},
	"pelvis/hip_right/knee_right/CalfRight": {"position": Vector2(511, 710), "z": 7},
	"pelvis/hip_right/knee_right/ankle_right/FootRight": {"position": Vector2(514, 1000), "z": 6},
	"pelvis/hip_left/ThighLeft": {"position": Vector2(619, 520), "z": 11},
	"pelvis/hip_left/knee_left/CalfLeft": {"position": Vector2(663, 710), "z": 10},
	"pelvis/hip_left/knee_left/ankle_left/FootLeft": {"position": Vector2(685, 1000), "z": 9},
}

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_check(packed != null, "scene loads")
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

	for path in EXPECTED_BONES:
		var bone := skeleton.get_node_or_null(path) as Bone2D
		_check(bone != null, "%s exists" % path)
		if bone != null:
			_check(bone.global_position.is_equal_approx(EXPECTED_BONES[path]), "%s pivot is correct" % path)
			_check(is_zero_approx(bone.rotation), "%s has neutral rotation" % path)
			_check(bone.scale.is_equal_approx(Vector2.ONE), "%s has no telescoping scale" % path)

	for path in EXPECTED_SPRITES:
		var sprite := skeleton.get_node_or_null(path) as Sprite2D
		_check(sprite != null, "%s exists" % path)
		if sprite != null:
			_check(not sprite.centered, "%s uses manifest top-left registration" % path)
			_check(sprite.texture != null, "%s has a texture" % path)
			_check(sprite.global_position.is_equal_approx(EXPECTED_SPRITES[path]["position"]), "%s registration is correct" % path)
			_check(sprite.z_index == EXPECTED_SPRITES[path]["z"], "%s layer is correct" % path)

	_check(skeleton.get_bone_count() == 15, "Skeleton2D registers exactly 15 bones")
	_finish()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)

func _finish() -> void:
	if failures.is_empty():
		print("FRONT NEUTRAL RIG GODOT VALIDATION PASSED")
		quit(0)
	else:
		printerr("VALIDATION FAILED (%d checks)" % failures.size())
		quit(1)
