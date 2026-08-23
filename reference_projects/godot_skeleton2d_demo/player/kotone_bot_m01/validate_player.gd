extends SceneTree

const PLAYER_SCENE := "res://player/kotone_bot_m01/player.tscn"
const LEVEL_SCENE := "res://level.tscn"


func _init() -> void:
	var packed_player := load(PLAYER_SCENE) as PackedScene
	_assert(packed_player != null, "replacement player scene loads")
	var player := packed_player.instantiate()
	_assert(player is CharacterBody2D, "root is CharacterBody2D")
	_assert(player.name == &"SkeletalPlayer", "root keeps level-facing player name")
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	_assert(camera != null, "player camera exists")
	_assert(camera.zoom == Vector2(6, 6), "camera enlarges the whole world uniformly")
	var visual := player.get_node("VisualPivot/Sprite2D") as Node2D
	_assert(visual.scale == Vector2(0.04, 0.04), "model keeps its world-relative scale")

	var skeleton := player.get_node_or_null("VisualPivot/Sprite2D/Skeleton2D") as Skeleton2D
	_assert(skeleton != null, "Skeleton2D exists")
	_assert(_count_type(skeleton, "Bone2D") == 15, "15 Bone2D nodes exist")

	var polygons_root := player.get_node_or_null("VisualPivot/Sprite2D/Polygons")
	_assert(polygons_root != null, "polygon container exists")
	_assert(polygons_root.get_child_count() == 6, "six whole-region polygons exist")
	for child in polygons_root.get_children():
		var polygon := child as Polygon2D
		_assert(polygon != null, "%s is Polygon2D" % child.name)
		_assert(polygon.skeleton == NodePath("../../Skeleton2D"), "%s binds shared skeleton" % child.name)
		_assert(polygon.polygon.size() > 4, "%s has authored mesh vertices" % child.name)
		_assert(polygon.internal_vertex_count == polygon.polygon.size(), "%s registers every mesh vertex" % child.name)

	var packed_level := load(LEVEL_SCENE) as PackedScene
	_assert(packed_level != null, "demo level loads")
	var level := packed_level.instantiate()
	var active_player := level.get_node_or_null("SkeletalPlayer")
	_assert(active_player != null, "demo level instantiates its player")
	_assert(active_player.scene_file_path == PLAYER_SCENE, "demo level selects Kotone-bot")

	player.free()
	level.free()
	print("KTN-RC3-M01 GBOT LEVEL GODOT VALIDATION PASSED")
	quit(0)


func _count_type(root: Node, type_name: String) -> int:
	var count := 0
	for child in root.get_children():
		if child.is_class(type_name):
			count += 1
		count += _count_type(child, type_name)
	return count


func _assert(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
		return
	push_error("FAIL: " + label)
	quit(1)
