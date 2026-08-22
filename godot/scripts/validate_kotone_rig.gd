extends SceneTree

const RIG_SCENE := "res://scenes/kotone_rig.tscn"
const MANIFEST := "res://assets/rc3/rig/rig_manifest.json"

func _init() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var packed := load(RIG_SCENE) as PackedScene
	if packed == null:
		_fail("Unable to load kotone_rig.tscn")
		return

	var rig := packed.instantiate()
	get_root().add_child(rig)
	var manifest_data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest_data is Dictionary:
		_fail("Unable to parse rig_manifest.json")
		return

	var expected: Dictionary = {}
	for layer in manifest_data.layers:
		expected["res://assets/rc3/rig/" + layer.file] = 0

	var sprites: Array[Sprite2D] = []
	_collect_sprites(rig, sprites)
	for sprite in sprites:
		if sprite.texture == null:
			_fail("Sprite without texture: " + str(sprite.get_path()))
			return
		var resource_path := sprite.texture.resource_path
		if not expected.has(resource_path):
			_fail("Unexpected rig texture: " + resource_path)
			return
		expected[resource_path] += 1

	if sprites.size() != expected.size():
		_fail("Expected 29 Sprite2D layers, found " + str(sprites.size()))
		return
	for resource_path in expected:
		if expected[resource_path] != 1:
			_fail("Texture is not connected exactly once: " + resource_path + " x" + str(expected[resource_path]))
			return

	var required_bones := [
		"pelvis", "torso", "neck", "head", "shoulder_near", "elbow_near", "wrist_near",
		"shoulder_far", "elbow_far", "wrist_far", "hip_near", "knee_near", "ankle_near",
		"hip_far", "knee_far", "ankle_far", "hair_near_control", "hair_far_control", "badge_control"
	]
	for bone_name in required_bones:
		if rig.find_child(bone_name, true, false) == null:
			_fail("Missing required Bone2D: " + bone_name)
			return

	if rig.scale != Vector2.ONE:
		_fail("Root rig scale is not 1.0")
		return

	var animation_player := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null or not animation_player.get_animation_library_list().is_empty():
		_fail("AnimationPlayer must be present and empty for the neutral rig")
		return

	var visible_variants := ["eye_near_open", "eye_far_open", "mouth_neutral"]
	var hidden_variants := ["eye_near_closed", "eye_far_closed", "mouth_smile"]
	for node_name in visible_variants:
		if not (rig.find_child(node_name, true, false) as Sprite2D).visible:
			_fail("Neutral variant is hidden: " + node_name)
			return
	for node_name in hidden_variants:
		if (rig.find_child(node_name, true, false) as Sprite2D).visible:
			_fail("Alternate variant is visible: " + node_name)
			return

	var far_foot := rig.find_child("shoe_far", true, false) as Sprite2D
	var near_foot := rig.find_child("shoe_near", true, false) as Sprite2D
	if far_foot == null or near_foot == null or absf(far_foot.global_position.y - near_foot.global_position.y) > 0.1:
		_fail("Neutral shoes do not share a floor line")
		return

	print("Kotone rig validation passed: %d unique PNG layers, required bones present, root scale 1.0, shoes aligned." % sprites.size())
	quit(0)

func _collect_sprites(node: Node, result: Array[Sprite2D]) -> void:
	if node is Sprite2D:
		result.append(node)
	for child in node.get_children():
		_collect_sprites(child, result)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
