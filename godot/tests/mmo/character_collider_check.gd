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
	var a := {"collision_width_mm":400,"collision_height_mm":1720}
	var b := {"collision_width_mm":360,"collision_height_mm":1550}
	check(Collider.install(owner,a,8.0),"owner shape installs")
	check(Collider.install(proxy,a,8.0),"proxy shape installs through same contract")
	check(owner.shape is RectangleShape2D and proxy.shape is RectangleShape2D,"native rectangle primitive")
	check(owner.shape.size == Vector2(3.2,13.76),"millimetres convert to Godot pixels")
	check(owner.position == Vector2(0.0,-6.88),"ground pivot centers rectangle half-height upward")
	check(proxy.shape.size == owner.shape.size and proxy.position == owner.position,
		"owner and peer proxy geometry are identical for one body profile")
	var owner_shape := owner.shape
	var proxy_shape := proxy.shape
	check(owner_shape != proxy_shape, "owner and peer own independent native resources")
	# In production every world projection re-installs the owner profile. That
	# must not replace the Shape2D the Remote Inspector and physics are using.
	var stable := true
	for tick in range(240):
		if not Collider.install(owner,a,8.0) or not Collider.install(proxy,a,8.0):
			stable = false
			break
		if owner.shape != owner_shape or proxy.shape != proxy_shape:
			stable = false
			break
	check(stable and owner.shape.size == Vector2(3.2,13.76)
		and owner.position == Vector2(0.0,-6.88) and not owner.disabled,
		"240 unchanged world projections preserve native shape identity and geometry")
	var body := CharacterBody2D.new()
	body.safe_margin = 0.0
	check(body.safe_margin == 0.0,
		"owner native contact has no client-only recovery inflation beyond server dimensions")
	body.free()
	var before_size: Vector2 = owner.shape.size
	var before_offset: Vector2 = owner.position
	var visual := Node2D.new()
	visual.scale = Vector2(4.0,0.25)
	visual.position = Vector2(99,77)
	check(owner.shape.size == before_size and owner.position == before_offset,
		"visual transform cannot mutate collider geometry")
	check(Collider.install(proxy,b,8.0),"second physical profile installs")
	check(proxy.shape == proxy_shape and owner.shape == owner_shape,
		"a legal profile geometry change updates the peer rectangle in place")
	check(Collider.install(proxy,b,8.0) and proxy.shape == proxy_shape,
		"subsequent peer profile projections do not replace the revised shape")
	check(is_equal_approx(proxy.shape.size.x,2.88) and is_equal_approx(proxy.shape.size.y,12.4)
		and is_equal_approx(proxy.position.x,0.0) and is_equal_approx(proxy.position.y,-6.2),
		"different physical dimensions produce different native shape")
	check(not Collider.install(proxy,{"collision_width_mm":0,"collision_height_mm":1550},8.0)
		and proxy.disabled and proxy.shape == null,"invalid geometry fails closed")
	check(not Collider.install(proxy,{"collision_width_mm":0,"collision_height_mm":1550},8.0)
		and proxy.disabled and proxy.shape == null,"repeated invalid profile stays disabled")
	check(Collider.install(proxy,a,8.0) and proxy.shape is RectangleShape2D
		and proxy.shape != proxy_shape and not proxy.disabled,
		"valid geometry re-installs a new rectangle after explicit invalidation")
	owner.free()
	proxy.free()
	visual.free()
	print(JSON.stringify({"suite":"character-collider-contract","checks":checks,"failures":failures,
		"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
