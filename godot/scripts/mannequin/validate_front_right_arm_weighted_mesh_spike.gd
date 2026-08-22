extends SceneTree

const SCENE_PATH := "res://scenes/mannequin/kotone_front_right_arm_weighted_mesh_spike.tscn"
const SOURCE_PATH := "res://assets/rc3/mannequin/source/kotone_front_mannequin_t_pose.png"
const EXPECTED_SHA256 := "b13044d02fbc96a405e83d7903099e5a6bb9f99a6b471ac9e171c63ffc734b34"
const EXPECTED_BONE_PATHS := [
	NodePath("../BaseRig/Skeleton2D/pelvis/torso/upper_arm_right"),
	NodePath("../BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right"),
	NodePath("../BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right/hand_right")
]

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_check_source()
	var packed := load(SCENE_PATH) as PackedScene
	_check(packed != null, "weighted arm scene loads")
	if packed == null:
		_finish()
		return
	var rig := packed.instantiate()
	get_root().add_child(rig)
	await process_frame
	var mesh := rig.get_node_or_null("FrontRightArmMesh") as Polygon2D
	var skeleton := rig.get_node_or_null("BaseRig/Skeleton2D") as Skeleton2D
	_check(mesh != null, "FrontRightArmMesh is present")
	_check(skeleton != null, "accepted neutral Skeleton2D is reused")
	if mesh == null or skeleton == null:
		_finish()
		return
	_check(mesh.texture != null and mesh.texture.resource_path == SOURCE_PATH, "approved mannequin source texture is used")
	_check(mesh.skeleton == NodePath("../BaseRig/Skeleton2D"), "mesh is bound to accepted neutral Skeleton2D")
	_check(mesh.polygon.size() == 45, "mesh has 45 vertices")
	_check(mesh.uv.size() == mesh.polygon.size(), "one UV exists per vertex")
	_check(mesh.internal_vertex_count == 15, "15 internal centerline vertices are present")
	_check(mesh.polygons.size() == 28, "28 explicit mesh cells are present")
	_check(mesh.get_bone_count() == 3, "upper arm, forearm and hand carry weights")
	for bone_index in mesh.get_bone_count():
		_check(mesh.get_bone_path(bone_index) == EXPECTED_BONE_PATHS[bone_index], "bone slot %d uses the approved path" % bone_index)
		_check(mesh.get_bone_weights(bone_index).size() == mesh.polygon.size(), "bone slot %d has one weight per vertex" % bone_index)
	for vertex_index in mesh.polygon.size():
		var total := 0.0
		for bone_index in mesh.get_bone_count():
			total += mesh.get_bone_weights(bone_index)[vertex_index]
		_check(absf(total - 1.0) < 0.01, "vertex %d weights normalize to one" % vertex_index)
	for path in [
		"BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/UpperArmRight",
		"BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right/ForearmRight",
		"BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right/hand_right/HandRight"
	]:
		var sprite := rig.get_node_or_null(path) as Sprite2D
		_check(sprite != null and not sprite.visible, "rigid sprite is hidden: %s" % path)
	var elbow := rig.get_node("BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right") as Bone2D
	var hand := rig.get_node("BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right/hand_right") as Bone2D
	_check(elbow.global_position.is_equal_approx(Vector2(414, 263)), "elbow pivot remains at approved coordinate")
	_check(hand.global_position.is_equal_approx(Vector2(300, 270)), "wrist pivot remains at approved coordinate")
	elbow.rotation = deg_to_rad(-18.0)
	_check(hand.global_position.y > 270.0, "-18 degrees bends anatomical-right forearm downward")
	_check(elbow.scale.is_equal_approx(Vector2.ONE), "elbow scale remains one")
	_finish()

func _check_source() -> void:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var source_file := FileAccess.open(SOURCE_PATH, FileAccess.READ)
	_check(source_file != null, "approved source file opens")
	if source_file != null:
		context.update(source_file.get_buffer(source_file.get_length()))
		_check(context.finish().hex_encode() == EXPECTED_SHA256, "approved source SHA-256 is unchanged")

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)

func _finish() -> void:
	if failures.is_empty():
		print("FRONT RIGHT ARM WEIGHTED MESH SPIKE GODOT VALIDATION PASSED")
		quit(0)
	else:
		printerr("FRONT RIGHT ARM WEIGHTED MESH SPIKE GODOT VALIDATION FAILED (%d checks)" % failures.size())
		quit(1)
