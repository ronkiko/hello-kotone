extends SceneTree

const PLAYER_SCENE := "res://player/kotone_bot_m02/player.tscn"
const LEVEL_SCENE := "res://level.tscn"


func _init() -> void:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate()
	_assert(player is CharacterBody2D, "M02 root is CharacterBody2D")
	_assert(player.get_node_or_null("Camera2D") is Camera2D, "camera exists")
	var skeleton := player.get_node("VisualPivot/Sprite2D/Skeleton2D")
	_assert(_count_named_prefix(skeleton, "Art_") == 15, "15 rigid art parts exist")
	_assert(_count_named_prefix(skeleton, "Joint_") == 24, "24 joint-cap layers exist")
	_assert(_count_type(skeleton, "Bone2D") == 15, "15 Bone2D nodes exist")

	var level := (load(LEVEL_SCENE) as PackedScene).instantiate()
	var active := level.get_node_or_null("SkeletalPlayer")
	_assert(active != null, "level player exists")
	_assert(active.scene_file_path == PLAYER_SCENE, "level selects M02")
	player.free()
	level.free()
	print("KTN-RC3-M02 SEGMENTED PLAYER GODOT VALIDATION PASSED")
	quit(0)


func _count_type(root: Node, type_name: String) -> int:
	var count := 0
	for child in root.get_children():
		if child.is_class(type_name):
			count += 1
		count += _count_type(child, type_name)
	return count


func _count_named_prefix(root: Node, prefix: String) -> int:
	var count := 0
	for child in root.get_children():
		if String(child.name).begins_with(prefix):
			count += 1
		count += _count_named_prefix(child, prefix)
	return count


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
		return
	push_error("FAIL: " + label)
	quit(1)
