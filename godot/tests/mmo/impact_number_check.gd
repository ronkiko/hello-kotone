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
	check(overlay.show_impact(fact(9, 8, 37900000), 74.4), "first server impact renders a damage number")
	check(overlay.get_child_count() == 1 and overlay.get_child(0).text == "-8",
		"number displays authoritative damage rather than a locally computed estimate")
	check(not overlay.show_impact(fact(9, 8, 37900000), 74.4) and overlay.get_child_count() == 1,
		"same causal tick cannot display twice")
	check(not overlay.show_impact(fact(10, 0, 0), 74.4), "no physical impact produces no popup")
	check(overlay.show_impact(fact(11, 12, 60000000), 74.4)
		and overlay.last_impact_tick == 11 and overlay.get_child_count() == 2,
		"new causal impact displays separately without resetting older animation")
	for tick in range(12, 22):
		check(overlay.show_impact(fact(tick, 1, 5000000), 74.4), "new unique hit accepted")
	check(overlay._visible.size() <= ImpactNumber.MAX_VISIBLE, "active popups are strictly bounded")
	await create_timer(2.2).timeout
	await process_frame
	check(overlay.get_child_count() == 0, "all popups expire automatically after two seconds")
	overlay.reset()
	check(overlay.last_impact_tick == 0 and overlay._visible.is_empty(),
		"new session clears causal deduplication and popup references")
	check(overlay.show_impact(fact(1, 3, 15000000), 74.4), "fresh scope can show a new hit")
	print(JSON.stringify({"suite":"impact-damage-overlay","checks":checks,
		"failures":failures,"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
