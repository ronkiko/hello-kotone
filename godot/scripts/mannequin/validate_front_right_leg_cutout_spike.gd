extends SceneTree

const SCENE_PATH := "res://scenes/mannequin/kotone_front_right_leg_cutout_spike.tscn"

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_check(packed != null, "scene loads")
	if packed == null:
		_finish()
		return
	var rig := packed.instantiate()
	get_root().add_child(rig)
	var skeleton := rig.get_node_or_null("Skeleton2D") as Skeleton2D
	_check(skeleton != null, "Skeleton2D exists")
	if skeleton == null:
		_finish()
		return
	var expected := {
		"pelvis": Vector2(627, 545),
		"pelvis/hip_right": Vector2(555, 565),
		"pelvis/hip_right/knee_right": Vector2(555, 765),
		"pelvis/hip_right/knee_right/ankle_right": Vector2(555, 1040),
	}
	for path in expected:
		var bone := skeleton.get_node_or_null(path) as Bone2D
		_check(bone != null, "%s exists" % path)
		if bone != null:
			_check(bone.global_position.is_equal_approx(expected[path]), "%s pivot is correct" % path)
			_check(is_zero_approx(bone.rotation), "%s has neutral rotation" % path)
			_check(bone.scale.is_equal_approx(Vector2.ONE), "%s has no telescoping scale" % path)
	var sprite_paths := [
		"pelvis/Pelvis",
		"pelvis/hip_right/ThighRight",
		"pelvis/hip_right/knee_right/CalfRight",
		"pelvis/hip_right/knee_right/ankle_right/FootRight",
	]
	for path in sprite_paths:
		var sprite := skeleton.get_node_or_null(path) as Sprite2D
		_check(sprite != null, "%s exists" % path)
		if sprite != null:
			_check(not sprite.centered, "%s uses manifest top-left offset" % path)
	_finish()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)

func _finish() -> void:
	if failures.is_empty():
		print("FRONT RIGHT LEG CUTOUT SPIKE GODOT VALIDATION PASSED")
		quit(0)
	else:
		printerr("VALIDATION FAILED (%d checks)" % failures.size())
		quit(1)
