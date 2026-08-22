extends SceneTree

const SCENE_PATH := "res://scenes/mannequin/kotone_front_right_arm_anatomical_mesh_spike.tscn"
const SOURCE_PATH := "res://assets/rc3/mannequin/source/kotone_front_mannequin_t_pose.png"
const EXPECTED_SHA256 := "b13044d02fbc96a405e83d7903099e5a6bb9f99a6b471ac9e171c63ffc734b34"
const EXPECTED_BONE_PATHS := [
	NodePath("../BaseRig/Skeleton2D/pelvis/torso/upper_arm_right"),
	NodePath("../BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right"),
	NodePath("../BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right/hand_right")
]
const ALLOWED_WEIGHTS := [0.0, 0.5, 1.0]

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_check_source()
	var packed := load(SCENE_PATH) as PackedScene
	_check(packed != null, "anatomical arm scene loads")
	if packed == null:
		_finish()
		return
	var rig := packed.instantiate()
	get_root().add_child(rig)
	await process_frame
	var mesh := rig.get_node_or_null("FrontRightArmMesh") as Polygon2D
	_check(mesh != null, "FrontRightArmMesh is present")
	if mesh == null:
		_finish()
		return
	_check(mesh.texture != null and mesh.texture.resource_path == SOURCE_PATH, "approved source texture is used")
	_check(mesh.skeleton == NodePath("../BaseRig/Skeleton2D"), "accepted neutral skeleton is reused")
	_check(mesh.polygon.size() == 24, "semantic mesh has 24 vertices")
	_check(mesh.uv.size() == 24, "one UV exists per mesh vertex")
	_check(mesh.internal_vertex_count == 2, "only elbow and wrist internal vertices are present")
	_check(mesh.polygons.size() == 18, "joint-local topology has 18 explicit cells")
	_check(mesh.get_bone_count() == 3, "three anatomical arm bones carry weights")
	for bone_index in mesh.get_bone_count():
		_check(mesh.get_bone_path(bone_index) == EXPECTED_BONE_PATHS[bone_index], "bone slot %d uses approved path" % bone_index)
		var weights := mesh.get_bone_weights(bone_index)
		_check(weights.size() == mesh.polygon.size(), "bone slot %d has one weight per vertex" % bone_index)
		for weight in weights:
			_check(ALLOWED_WEIGHTS.has(weight), "weight %.3f is joint-local 0, 0.5 or 1" % weight)
	for vertex_index in mesh.polygon.size():
		var total := 0.0
		var partial_count := 0
		for bone_index in mesh.get_bone_count():
			var weight := mesh.get_bone_weights(bone_index)[vertex_index]
			total += weight
			partial_count += int(is_equal_approx(weight, 0.5))
		_check(is_equal_approx(total, 1.0), "vertex %d weights normalize to one" % vertex_index)
		_check(partial_count == 0 or partial_count == 2, "vertex %d is rigid or shared by exactly two adjacent bones" % vertex_index)
	var elbow := rig.get_node("BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right") as Bone2D
	var hand := rig.get_node("BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right/hand_right") as Bone2D
	_check(elbow.global_position.is_equal_approx(Vector2(414, 263)), "elbow pivot remains approved")
	_check(hand.global_position.is_equal_approx(Vector2(300, 270)), "wrist pivot remains approved")
	var previous_y := hand.global_position.y
	for angle in [-30.0, -60.0, -90.0]:
		elbow.rotation = deg_to_rad(angle)
		_check(hand.global_position.y > previous_y, "elbow %d degrees moves wrist farther downward" % int(absf(angle)))
		previous_y = hand.global_position.y
		_check(elbow.scale.is_equal_approx(Vector2.ONE), "elbow scale remains one at %d degrees" % int(absf(angle)))
	_finish()

func _check_source() -> void:
	var source_file := FileAccess.open(SOURCE_PATH, FileAccess.READ)
	_check(source_file != null, "approved source file opens")
	if source_file == null:
		return
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
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
		print("FRONT RIGHT ARM ANATOMICAL MESH SPIKE GODOT VALIDATION PASSED")
		quit(0)
	else:
		printerr("FRONT RIGHT ARM ANATOMICAL MESH SPIKE GODOT VALIDATION FAILED (%d checks)" % failures.size())
		quit(1)
