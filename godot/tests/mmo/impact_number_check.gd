extends SceneTree
const ImpactNumber = preload("res://scripts/presentation/impact_number.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fact(tick: int, damage: int, impulse: int) -> Dictionary:
	return {"contact_response_tick":tick, "contact_damage":damage,
		"contact_impact_impulse_g_mm_s":impulse,
		"contact_impact_sources":["p1"] if impulse > 0 else []}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var overlay := ImpactNumber.new()
	root.add_child(overlay)
	overlay.display_enabled = true
	overlay.stagger_seconds = 0.04
	var point := Vector2(240, 96)
	check(overlay.show_impact(fact(9, 8, 37900000), point),
		"first server impact enters FIFO dispatcher")
	check(overlay.get_child_count() == 1 and overlay.get_child(0).text == "-8",
		"first event is rendered immediately using authoritative damage")
	check(overlay.get_child(0).position.y == point.y,
		"renderer receives an explicit fixed world point, not a moving parent offset")
	check(not overlay.show_impact(fact(9, 8, 37900000), point)
		and overlay.get_child_count() == 1 and overlay._pending.is_empty(),
		"duplicate causal tick cannot enqueue a second visual")
	check(not overlay.show_impact(fact(10, 0, 0), point),
		"zero-damage contact does not enter the queue")
	check(overlay.show_impact(fact(11, 12, 60000000), point)
		and overlay._pending.size() == 1 and overlay.get_child_count() == 1,
		"subsequent event waits for its display interval")
	# Deliberately exceed the former MAX_VISIBLE=4. FIFO keeps every valid event.
	for tick in range(12, 44):
		check(overlay.show_impact(fact(tick, 1, 5000000), point),
			"burst events are all admitted in arrival order")
	check(overlay._pending.size() == 33 and overlay.get_child_count() == 1,
		"no pending damage is dropped due to the number of visible labels")
	for i in range(33):
		overlay._process(0.041)
	check(overlay._pending.is_empty() and overlay.get_child_count() == 34,
		"dispatcher eventually renders all 34 hits without a visible-quantity cap")
	check(overlay.get_child(0).text == "-8" and overlay.get_child(1).text == "-12"
		and overlay.get_child(2).text == "-1",
		"burst damage is rendered FIFO")
	await create_timer(2.2).timeout
	await process_frame
	check(overlay.get_child_count() == 0,
		"each fully rendered number frees itself two seconds after presentation")
	check(overlay.show_impact(fact(44, 2, 10000000), point)
		and overlay.show_impact(fact(45, 3, 15000000), point),
		"new impact begins a new display sequence")
	overlay.reset()
	await process_frame
	check(overlay._pending.is_empty() and overlay.get_child_count() == 0
		and overlay.last_impact_tick == 0,
		"scope reset clears only stale-session events and active visual lifetimes")
	overlay.display_enabled = false
	check(not overlay.show_impact(fact(46, 4, 20000000), point)
		and overlay._pending.is_empty() and overlay.get_child_count() == 0,
		"project display flag suppresses rendering without altering server facts")
	overlay.display_enabled = true
	check(overlay.show_impact(fact(1, 3, 15000000), point),
		"reenabled overlay accepts a fresh scoped event")
	overlay.reset()
	await process_frame
	check(overlay.get_child_count() == 0, "reset terminates popup-owned tweens")
	print(JSON.stringify({"suite":"impact-damage-fifo","checks":checks,
		"failures":failures,"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
