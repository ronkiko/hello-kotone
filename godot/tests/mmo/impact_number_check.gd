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
	var effects: Node2D = EffectsScene.instantiate()
	root.add_child(effects)
	effects.display_enabled = true
	var left := Vector2(240, 96)
	var right := Vector2(440, 70)
	effects.show_damage(8, left)
	effects.show_damage(12, right)
	check(effects.get_child_count() == 2,
		"same world presenter accepts multiple characters without FIFO delay")
	var first: Node2D = effects.get_child(0)
	var second: Node2D = effects.get_child(1)
	check(first.global_position == left and second.global_position == right,
		"hit origins are fixed world positions, independent from character motion")
	check(first.get_node("Label").text == "-8" and second.get_node("Label").text == "-12",
		"number scenes contain the authoritative server-scored values")
	check(first.get_node("AnimationPlayer").is_playing()
		and second.get_node("AnimationPlayer").get_animation("float_and_fade").length == 2.0,
		"standard Godot AnimationPlayer owns each floating fade")
	for amount in range(1, 33):
		effects.show_damage(amount, left)
	check(effects.get_child_count() == 34,
		"34 rapid numbers all display independently; no visual cap or eviction")
	await create_timer(2.2).timeout
	await process_frame
	check(effects.get_child_count() == 0,
		"animation_finished frees every node after two seconds")
	effects.show_damage(3, left)
	effects.clear()
	await process_frame
	check(effects.get_child_count() == 0,
		"scope shutdown removes remaining cosmetic scenes without pending tweens")
	effects.display_enabled = false
	effects.show_damage(99, right)
	check(effects.get_child_count() == 0,
		"disabled VFX only suppresses presentation")
	print(JSON.stringify({"suite":"native-damage-effects",
		"checks":checks,"failures":failures,
		"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
