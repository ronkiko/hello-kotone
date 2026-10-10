extends SceneTree
const EffectsScene: PackedScene = preload("res://scenes/mmo/damage_effects.tscn")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var effects: Node2D = EffectsScene.instantiate() as Node2D
	root.add_child(effects)
	effects.set("display_enabled", true)
	var left := Vector2(240, 96)
	var right := Vector2(440, 70)
	effects.call(&"show_damage", 8, left)
	effects.call(&"show_damage", 12, right)
	check(effects.get_child_count() == 2,
		"same world presenter accepts multiple characters without FIFO delay")
	var first: Node2D = effects.get_child(0) as Node2D
	var second: Node2D = effects.get_child(1) as Node2D
	check(first.global_position == left and second.global_position == right,
		"hit origins are fixed world positions, independent from character motion")
	check((first.get_node("Label") as Label).text == "-8" and (second.get_node("Label") as Label).text == "-12",
		"number scenes contain the authoritative server-scored values")
	check((first.get_node("AnimationPlayer") as AnimationPlayer).is_playing()
		and (second.get_node("AnimationPlayer") as AnimationPlayer).get_animation("float_and_fade").length == 2.0,
		"standard Godot AnimationPlayer owns each floating fade")
	for amount in range(1, 33):
		effects.call(&"show_damage", amount, left)
	check(effects.get_child_count() == 34,
		"34 rapid numbers all display independently; no visual cap or eviction")
	await create_timer(2.2).timeout
	await process_frame
	check(effects.get_child_count() == 0,
		"animation_finished frees every node after two seconds")
	effects.call(&"show_damage", 3, left)
	effects.call(&"clear")
	await process_frame
	check(effects.get_child_count() == 0,
		"scope shutdown removes remaining cosmetic scenes without pending tweens")
	effects.set("display_enabled", false)
	effects.call(&"show_damage", 99, right)
	check(effects.get_child_count() == 0,
		"disabled VFX only suppresses presentation")
	print(JSON.stringify({"suite":"native-damage-effects",
		"checks":checks,"failures":failures,
		"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
