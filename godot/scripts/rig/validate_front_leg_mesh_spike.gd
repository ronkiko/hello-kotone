extends SceneTree

const SCENE_PATH := "res://scenes/rig/kotone_front_leg_mesh_spike.tscn"
const SOURCE_PATH := "res://assets/rc3/rig/source/kotone_front_t_pose.png"
const QA_PATH := "res://assets/rc3/rig/source/kotone_front_t_pose.qa.json"
const EXPECTED_SHA256 := "ebf49c3444844173f02ee32ed6697396868411ab945de7a35500f28e21532d39"
const EXPECTED_BONES := ["hip_right", "knee_right", "ankle_right"]
const EXPECTED_BONE_PATHS := ["pelvis/hip_right", "pelvis/hip_right/knee_right", "pelvis/hip_right/knee_right/ankle_right"]
const EXPECTED_MESH_BONE_PATHS := [
	NodePath("../Skeleton2D/pelvis/hip_right"),
	NodePath("../Skeleton2D/pelvis/hip_right/knee_right"),
	NodePath("../Skeleton2D/pelvis/hip_right/knee_right/ankle_right")
]
const EXPECTED_PIVOTS := [Vector2(555, 560), Vector2(555, 765), Vector2(555, 1040)]

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_check_source()
	var packed := load(SCENE_PATH) as PackedScene
	_check(packed != null, "scene loads")
	if packed == null:
		_finish()
		return
	var rig := packed.instantiate()
	get_root().add_child(rig)
	var skeleton := rig.get_node_or_null("Skeleton2D") as Skeleton2D
	_check(skeleton != null, "Skeleton2D is present")
	if skeleton == null:
		_finish()
		return
	var expected_parents := ["pelvis", "hip_right", "knee_right"]
	for index in EXPECTED_BONES.size():
		var bone := skeleton.get_node_or_null(EXPECTED_BONE_PATHS[index]) as Bone2D
		_check(bone != null, "required bone %s is present" % EXPECTED_BONES[index])
		if bone != null:
			_check(bone.get_parent().name == expected_parents[index], "%s has the required parent" % EXPECTED_BONES[index])
			_check(bone.rest.is_equal_approx(bone.transform), "%s rest transform is stable" % EXPECTED_BONES[index])
			_check(bone.global_position.is_equal_approx(EXPECTED_PIVOTS[index]), "%s pivot is at approved source coordinate %s" % [EXPECTED_BONES[index], EXPECTED_PIVOTS[index]])

	var polygons := _find_polygons(rig)
	_check(polygons.size() == 1, "exactly one working Polygon2D is present")
	_check(_find_sprites(rig).is_empty(), "no Sprite2D limb segments are present")
	if polygons.size() != 1:
		_finish()
		return
	var leg := polygons[0]
	_check(leg.name == "FrontLegMesh", "working Polygon2D is named FrontLegMesh")
	_check(leg.polygon.size() > 0, "polygon is populated")
	_check(leg.uv.size() == leg.polygon.size(), "polygon and uv vertex counts agree (%d)" % leg.polygon.size())
	_check(leg.polygons.size() > 0, "explicit mesh polygons are populated (%d cells)" % leg.polygons.size())
	for mesh_polygon in leg.polygons:
		_check(mesh_polygon.size() >= 3, "mesh cell has at least three indices")
		for vertex_index in mesh_polygon:
			_check(vertex_index >= 0 and vertex_index < leg.polygon.size(), "mesh index %d is in range" % vertex_index)
	_check(leg.internal_vertex_count > 0, "internal vertices are present (%d)" % leg.internal_vertex_count)
	_check(leg.skeleton == NodePath("../Skeleton2D"), "Polygon2D is bound to Skeleton2D")
	_check(leg.texture != null and leg.texture.resource_path == SOURCE_PATH, "approved T-pose texture is used")
	_check(leg.get_bone_count() == 3, "three weighted bones are assigned")
	var positive_bones := 0
	for index in leg.get_bone_count():
		_check(leg.get_bone_path(index) == EXPECTED_MESH_BONE_PATHS[index], "bone slot %d is bound to %s" % [index, EXPECTED_MESH_BONE_PATHS[index]])
		var weights := leg.get_bone_weights(index)
		_check(weights.size() == leg.polygon.size(), "bone %d has one weight per vertex" % index)
		var positive := 0
		for weight in weights:
			if weight > 0.001:
				positive += 1
		positive_bones += int(positive > 0)
		_check(positive > 0, "bone %d has positive assigned weights" % index)
	for vertex in leg.polygon.size():
		var total := 0.0
		for bone_index in leg.get_bone_count():
			total += leg.get_bone_weights(bone_index)[vertex]
		_check(absf(total - 1.0) < 0.01, "vertex %d weights normalize to 1" % vertex)
		var expected := _expected_weights(leg.polygon[vertex].y)
		for bone_index in leg.get_bone_count():
			var actual := leg.get_bone_weights(bone_index)[vertex]
			_check(absf(actual - expected[bone_index]) < 0.01, "vertex %d bone %d uses localized joint weight" % [vertex, bone_index])
	_check(positive_bones == 3, "hip_right, knee_right and ankle_right all carry weights")
	_check(leg.polygon.size() == 72, "mesh has 72 vertices")
	_check(leg.uv[0] == Vector2(511, 575) and leg.uv[leg.uv.size() - 1] == Vector2(546, 1150), "UVs remain in approved source coordinates")
	_print_summary(leg, skeleton)
	_finish()

func _check_source() -> void:
	var source := load(SOURCE_PATH) as Texture2D
	_check(source != null, "approved source texture loads")
	var qa_file := FileAccess.open(QA_PATH, FileAccess.READ)
	_check(qa_file != null, "source QA record loads")
	if qa_file == null:
		return
	var qa = JSON.parse_string(qa_file.get_as_text())
	_check(qa is Dictionary and qa.get("status") == "ready_for_user_review", "revised source QA status is ready_for_user_review")
	_check(qa is Dictionary and qa.get("sha256") == EXPECTED_SHA256, "source QA SHA-256 matches revised source")
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var source_file := FileAccess.open(SOURCE_PATH, FileAccess.READ)
	if source_file != null:
		context.update(source_file.get_buffer(source_file.get_length()))
		_check(context.finish().hex_encode() == EXPECTED_SHA256, "source file SHA-256 matches QA record")

func _expected_weights(y: float) -> Vector3:
	if y <= 735.0:
		return Vector3(1.0, 0.0, 0.0)
	if y < 795.0:
		var knee_blend := (y - 735.0) / 60.0
		return Vector3(1.0 - knee_blend, knee_blend, 0.0)
	if y <= 1010.0:
		return Vector3(0.0, 1.0, 0.0)
	if y < 1070.0:
		var ankle_blend := (y - 1010.0) / 60.0
		return Vector3(0.0, 1.0 - ankle_blend, ankle_blend)
	return Vector3(0.0, 0.0, 1.0)

func _find_polygons(root: Node) -> Array[Polygon2D]:
	var result: Array[Polygon2D] = []
	for child in root.get_children():
		if child is Polygon2D:
			result.append(child)
		if child is Node:
			result.append_array(_find_polygons(child))
	return result

func _find_sprites(root: Node) -> Array[Sprite2D]:
	var result: Array[Sprite2D] = []
	for child in root.get_children():
		if child is Sprite2D:
			result.append(child)
		elif child is Node:
			result.append_array(_find_sprites(child))
	return result

func _print_summary(leg: Polygon2D, skeleton: Skeleton2D) -> void:
	print("PASS: Skeleton2D=%s bones=%d polygon_vertices=%d internal_vertices=%d weighted_bones=%d" % [skeleton.name, EXPECTED_BONES.size() + 1, leg.polygon.size(), leg.internal_vertex_count, leg.get_bone_count()])
	for index in leg.get_bone_count():
		var weights := leg.get_bone_weights(index)
		var nonzero := 0
		for weight in weights:
			if weight > 0.001:
				nonzero += 1
		print("PASS: %s weights positive_vertices=%d" % [leg.get_bone_path(index), nonzero])

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)

func _finish() -> void:
	if failures.is_empty():
		print("VALIDATION PASSED")
		quit(0)
	else:
		printerr("VALIDATION FAILED (%d checks)" % failures.size())
		quit(1)
