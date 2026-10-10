extends SceneTree
const ImpactNumber = preload("res://scripts/presentation/impact_number.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var renderer := ImpactNumber.new()
	root.add_child(renderer)
	renderer.display_enabled = true
	var place_a := Vector2(240, 96)
	var place_b := Vector2(450, 70)
	check(renderer.render_number(8, place_a), "first number renders immediately")
	check(renderer.render_number(12, place_b), "second number renders immediately")
	check(renderer.get_child_count() == 2
		and renderer.get_child(0).text == "-8"
		and renderer.get_child(1).text == "-12",
		"single renderer accepts different character hits without FIFO delay")
	check(renderer.get_child(0).position == place_a + Vector2(-36, 0)
		and renderer.get_child(1).position == place_b + Vector2(-36, 0),
		"numbers preserve independent fixed world-space hit coordinates")
	# Every number is rendered at arrival, including bursts > former MAX_VISIBLE.
	for hit in range(32):
		check(renderer.render_number(hit + 1, place_a), "rapid impact displays immediately")
	check(renderer.get_child_count() == 34,
		"burst preserves all 34 independent popup lifetimes without cap or queue")
	check(not renderer.render_number(0, place_b) and renderer.get_child_count() == 34,
		"zero damage never produces a visual")
	await create_timer(2.2).timeout
	await process_frame
	check(renderer.get_child_count() == 0, "each number expires after two seconds")
	check(renderer.render_number(4, place_a), "next event renders after preceding animation")
	renderer.reset()
	await process_frame
	check(renderer.get_child_count() == 0,
		"scene/scope reset stops each popup-owned Tween")
	renderer.display_enabled = false
	check(not renderer.render_number(9, place_b) and renderer.get_child_count() == 0,
		"disabled presentation suppresses visuals only")
	renderer.display_enabled = true
	check(renderer.render_number(3, place_b), "display can be reenabled without queue")
	renderer.reset()
	await process_frame
	check(renderer.get_child_count() == 0, "last popup reset is safe")
	print(JSON.stringify({"suite":"impact-damage-global-renderer","checks":checks,
		"failures":failures,"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
