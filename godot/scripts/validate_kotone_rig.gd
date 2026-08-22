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

	var bones: Array[Bone2D] = []
	_collect_bones(rig, bones)
	for bone in bones:
		if not bone.transform.is_equal_approx(bone.rest):
			_fail("Bone transform differs from rest pose: " + bone.name)
			return
		var rest_origin := bone.global_position
		bone.apply_rest()
		if bone.global_position.distance_to(rest_origin) > 0.01:
			_fail("Applying rest pose moved bone: " + bone.name)
			return

	var far_foot := rig.find_child("shoe_far", true, false) as Sprite2D
	var near_foot := rig.find_child("shoe_near", true, false) as Sprite2D
	if far_foot == null or near_foot == null:
		_fail("Missing neutral shoes")
		return
	var far_sole := _sprite_bottom(far_foot)
	var near_sole := _sprite_bottom(near_foot)
	if absf(far_sole - near_sole) > 3.0:
		_fail("Neutral soles do not share a floor line")
		return
	var ground_y := float(manifest_data.ground_line_y)
	if absf(((far_sole + near_sole) * 0.5) - ground_y) > 16.0:
		_fail("Neutral soles are too far from manifest ground_y: %.1f vs %.1f" % [((far_sole + near_sole) * 0.5), ground_y])
		return

	var torso_sprite := _sprite(rig, "torso")
	var skirt_sprite := _sprite(rig, "pelvis_skirt")
	var far_forearm := _sprite(rig, "arm_far_forearm")
	var far_hand := _sprite(rig, "hand_far")
	var near_upper := _sprite(rig, "arm_near_upper")
	var near_forearm := _sprite(rig, "arm_near_forearm")
	var near_hand := _sprite(rig, "hand_near")
	var far_thigh := _sprite(rig, "leg_far_thigh")
	var near_thigh := _sprite(rig, "leg_near_thigh")
	var far_calf := _sprite(rig, "leg_far_calf")
	var near_calf := _sprite(rig, "leg_near_calf")
	if torso_sprite == null or skirt_sprite == null or far_forearm == null or far_hand == null or near_upper == null or near_forearm == null or near_hand == null or far_thigh == null or near_thigh == null or far_calf == null or near_calf == null:
		_fail("Missing layer required for z-order validation")
		return
	if far_forearm.z_index >= torso_sprite.z_index or far_hand.z_index >= torso_sprite.z_index:
		_fail("Far arm lower layers must remain behind the torso")
		return
	if near_upper.z_index <= torso_sprite.z_index or near_forearm.z_index <= torso_sprite.z_index or near_hand.z_index <= torso_sprite.z_index:
		_fail("Near arm must remain above the torso")
		return
	if far_thigh.z_index >= skirt_sprite.z_index or near_thigh.z_index >= skirt_sprite.z_index or far_calf.z_index >= skirt_sprite.z_index or near_calf.z_index >= skirt_sprite.z_index:
		_fail("Both legs must remain behind the skirt")
		return
	if near_thigh.z_index <= far_thigh.z_index or near_calf.z_index <= far_calf.z_index:
		_fail("Near leg must draw above the far leg while staying behind the skirt")
		return

	var chain_limits := {
		["shoulder_far", "elbow_far"]: 210.0,
		["elbow_far", "wrist_far"]: 190.0,
		["shoulder_near", "elbow_near"]: 210.0,
		["elbow_near", "wrist_near"]: 190.0,
		["hip_far", "knee_far"]: 210.0,
		["knee_far", "ankle_far"]: 250.0,
		["hip_near", "knee_near"]: 210.0,
		["knee_near", "ankle_near"]: 250.0,
		["neck", "head"]: 90.0
	}
	for chain in chain_limits:
		var first := _bone(rig, chain[0])
		var second := _bone(rig, chain[1])
		if first == null or second == null or first.global_position.distance_to(second.global_position) > float(chain_limits[chain]):
			_fail("Unexpected gap in bone chain: %s -> %s" % [chain[0], chain[1]])
			return

	print("Kotone rig validation passed: %d unique PNG layers, rest pose stable, soles aligned at %.1f, z-order and limb chains valid." % [sprites.size(), ((far_sole + near_sole) * 0.5)])
	quit(0)

func _collect_sprites(node: Node, result: Array[Sprite2D]) -> void:
	if node is Sprite2D:
		result.append(node)
	for child in node.get_children():
		_collect_sprites(child, result)

func _collect_bones(node: Node, result: Array[Bone2D]) -> void:
	if node is Bone2D:
		result.append(node)
	for child in node.get_children():
		_collect_bones(child, result)

func _bone(rig: Node, bone_name: String) -> Bone2D:
	return rig.find_child(bone_name, true, false) as Bone2D

func _sprite(node: Node, sprite_name: String) -> Sprite2D:
	if node is Sprite2D and node.name == sprite_name:
		return node as Sprite2D
	for child in node.get_children():
		var result := _sprite(child, sprite_name)
		if result != null:
			return result
	return null

func _sprite_bottom(sprite: Sprite2D) -> float:
	var image := sprite.texture.get_image()
	var used := image.get_used_rect()
	return sprite.global_position.y + float(used.position.y + used.size.y) - (float(image.get_height()) * 0.5)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
