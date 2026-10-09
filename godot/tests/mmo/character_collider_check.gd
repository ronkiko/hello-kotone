extends SceneTree
const Collider = preload("res://scripts/presentation/character_collider.gd")
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func _initialize() -> void:
	var owner := CollisionShape2D.new()
	var proxy := CollisionShape2D.new()
	var a := {"collision_width_mm":400,"collision_height_mm":1700}
	var b := {"collision_width_mm":320,"collision_height_mm":1550}
	check(Collider.install(owner,a,8.0),"owner shape installs")
	check(Collider.install(proxy,a,8.0),"proxy shape installs through same contract")
	check(owner.shape is RectangleShape2D and proxy.shape is RectangleShape2D,"native rectangle primitive")
	check(owner.shape.size == Vector2(3.2,13.6),"millimetres convert to Godot pixels")
	check(owner.position == Vector2(0.0,-6.8),"ground pivot centers rectangle half-height upward")
	check(proxy.shape.size == owner.shape.size and proxy.position == owner.position,
		"owner and peer proxy geometry are identical for one body profile")
	var before_size: Vector2 = owner.shape.size
	var before_offset: Vector2 = owner.position
	var visual := Node2D.new()
	visual.scale = Vector2(4.0,0.25)
	visual.position = Vector2(99,77)
	check(owner.shape.size == before_size and owner.position == before_offset,
		"visual transform cannot mutate collider geometry")
	check(Collider.install(proxy,b,8.0),"second physical profile installs")
	check(proxy.shape.size == Vector2(2.56,12.4) and proxy.position == Vector2(0.0,-6.2),
		"different physical dimensions produce different native shape")
	check(not Collider.install(proxy,{"collision_width_mm":0,"collision_height_mm":1550},8.0)
		and proxy.disabled and proxy.shape == null,"invalid geometry fails closed")
	owner.free()
	proxy.free()
	visual.free()
	print(JSON.stringify({"suite":"character-collider-contract","checks":checks,"failures":failures,
		"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
