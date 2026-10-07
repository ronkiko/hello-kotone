extends SceneTree
const Fixtures = preload("res://tests/mmo/replica_check.gd")
const MOVEMENT := {"physics_hz":60,"publication_hz":20,"control_interval_ms":50,
	"engage_ms":100,"top_speed_mm_s":3000,"mass_g":70000,"width_mm":400,
	"drive_force_mN":560000,"brake_force_mN":560000}
const DT := 1.0 / 60.0
var checks := 0
var failures := []
var client: Node
var platform: Node2D
class PhysicsDriver extends Node:
	var test: SceneTree
	func _physics_process(_delta: float) -> void:
		set_physics_process(false)
		test.run()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	boot.call_deferred()
func boot() -> void:
	client = root.get_node("MmoClient")
	client.set_process(false)
	var platform_script: GDScript = load("res://scripts/presentation/platform_world.gd")
	platform = platform_script.new()
	root.add_child(platform)
	platform.set_process(false)
	platform.set_physics_process(false)
	check(platform.set_movement_rules({"movement":MOVEMENT}), "validated native motion rules")
	var player := Fixtures.player()
	var reference := {"map_id":Fixtures.MAP.map_id,"content_version":Fixtures.MAP.content_version,"content_hash":Fixtures.MAP.content_hash}
	check(platform.project(Fixtures.MAP, {"map":reference,"players":{"p1":player},
		"local_player_id":"p1","confirmed_local_position_mm":50000}), "initial owner projection")
	var driver := PhysicsDriver.new()
	driver.test = self
	root.add_child(driver)
func motion(tick: int, position: int, velocity: int = 3000, contacts: Array = []) -> Dictionary:
	return {"simulation_tick":tick,"position_mm":position,"velocity_mm_s":velocity,
		"facing":1,"last_applied_control_seq":1,"contacts":contacts}
func body_mm() -> int:
	return platform._pixel_to_server_mm(platform.character_root.position.x)
func reset(tick: int = 100, position: int = 50000) -> void:
	client._clear_session()
	client.state = "READY"
	client._world_rules = {"movement":MOVEMENT}
	client._desired_input = {"drive":1,"facing":1}
	client._server_input = client._desired_input.duplicate()
	client._server_input_seq = 1
	platform._prediction_fenced = false
	platform._resync_requested = false
	platform._apply_authoritative_motion(motion(tick, position), true)
func ticks(count: int) -> void:
	for _i in range(count): platform._physics_process(DT)
func run() -> void:
	check(Engine.is_in_physics_frame(), "native replay exercised in physics callback")
	reset()
	ticks(4)
	check(platform._prediction_history.size() == 4, "acknowledged held control records every physics interval")
	check(body_mm() == 50200, "native four-tick held movement")
	platform._apply_authoritative_motion(motion(102,50100),false)
	check(body_mm() == 50200 and platform._prediction_metrics.last_replayed_ticks == 2,
		"state at 102 replays 103 and 104 with unchanged confirmed control sequence")
	check(platform._prediction_history[0].simulation_tick == 103 and platform._prediction_history[1].simulation_tick == 104,
		"history pruned only through authoritative simulation marker")
	check(platform._prediction_metrics.max_divergence_mm == 0,
		"normal future travel is not charged as reconciliation divergence")
	for _i in range(6):
		ticks(3)
		var marker: int = platform._prediction_tick - 2
		var before := body_mm()
		platform._apply_authoritative_motion(motion(marker,50000 + (marker-100)*50),false)
		check(body_mm() == before and platform._prediction_history.size() == 2,
			"successive 20Hz samples preserve collision-body continuity with held seq1")
	reset()
	ticks(2)
	client.state = "MOVING"
	client._server_input = {"drive":0,"facing":1}
	client._server_input_seq = 0
	client._pending = {"op":"control_set","payload":{"control_seq":1,"drive":1,"facing":1}}
	client.set_control(0,1)
	ticks(1)
	check(not client.prediction_control_state().has("control_seq"), "predictor does not fabricate a future wire sequence")
	client.set_control(1,1)
	ticks(1)
	var present := body_mm()
	client._pending = {}
	client._server_input = {"drive":1,"facing":1}
	client._server_input_seq = 1
	client.state = "READY"
	client._schedule_desired_input()
	check(client._scheduled.is_empty() and client._server_input_seq == 1,
		"STOP coalesced away before ACK consumes no wire sequence")
	platform._apply_authoritative_motion(motion(102,50100),false)
	check(body_mm() == present and platform._prediction_history.size() == 2,
		"short local STOP interval replays once at its real tick")
	check(platform._prediction_history[0].drive == 0 and platform._prediction_history[1].drive == 1,
		"local STOP then RIGHT retain temporal order")
	# STOP never reached the wire: server at 103 is still on the RIGHT curve.
	platform._apply_authoritative_motion(motion(103,50150),false)
	check(platform._prediction_history.size() == 1 and platform._prediction_history[0].drive == 1 and body_mm() == 50200,
		"advancing authoritative marker retires STOP and restores server RIGHT curve despite unchanged seq1")
	platform._apply_authoritative_motion(motion(104,body_mm()),false)
	check(platform._prediction_history.is_empty(), "no ghost control survives confirmation of its interval")
	ticks(1)
	check(platform._prediction_history.size() == 1 and platform._prediction_history[0].drive == 1,
		"future physics remains RIGHT without phantom STOP")
	reset(100,99650)
	ticks(3)
	var snaps: int = platform._prediction_metrics.snaps
	platform._apply_authoritative_motion(motion(102,99750),false)
	check(platform._prediction_metrics.snaps == snaps and absi(body_mm()-99800) <= 2,
		"contact comparison uses state at marker, not later predicted wall contact")
	platform._apply_authoritative_motion(motion(103,99800,0,["wall_max"]),false)
	check(platform._predicted_contacts == ["wall_max"] and platform.character_root.velocity.x == 0.0,
		"authoritative wall contact retained with empty replay")
	reset()
	ticks(3)
	snaps = platform._prediction_metrics.snaps
	platform._apply_authoritative_motion(motion(101,50050,3000,["peer"]),false)
	check(platform._prediction_metrics.snaps == snaps + 1 and platform.visual_layer.position.x == 0.0,
		"server contact mismatch snaps after temporal replay")
	reset()
	ticks(2)
	platform._apply_authoritative_motion(motion(102,50120),false)
	check(platform._blend_remaining == 0.1 and absf(platform.visual_layer.position.x) <= 2.0,
		"small present correction uses bounded 100ms visual blend")
	platform._process(0.1)
	check(platform.visual_layer.position.x == 0.0, "blend converges within 100ms")
	platform._apply_authoritative_motion(motion(103,51000),false)
	check(platform._blend_remaining == 0.0 and platform.visual_layer.position.x == 0.0,
		"large present correction snaps")
	check(platform._prediction_tick == 103 and platform._prediction_history.is_empty(),
		"ahead-of-client sample advances anchor without inventing missing local intervals")
	reset()
	ticks(4)
	platform.set_suspended(true)
	client._clear_session()
	client.state = "READY"
	platform.set_suspended(false)
	platform._queue_snapshot_motion({"players":[Fixtures.player()]})
	ticks(1)
	check(platform._prediction_tick == 1 and platform._prediction_history.size() == 1
		and platform._prediction_history[0].drive == 0 and body_mm() == 50000,
		"fresh snapshot resets tick namespace and replays no previous-session control")
	reset()
	ticks(40)
	check(platform._prediction_history.size() == 40 and not platform._prediction_fenced,
		"bounded history retains exactly 40 intervals")
	ticks(1)
	check(platform._prediction_fenced and platform._prediction_history.is_empty() and client._desired_input.drive == 0,
		"41st interval fences, clears history and requests stop")
	reset()
	ticks(1)
	platform._prediction_history[0].at_ms = Time.get_ticks_msec()-2001
	ticks(1)
	check(platform._prediction_fenced and platform._prediction_history.is_empty(), "2s age ceiling fences")
	client._clear_session()
	platform.queue_free()
	print(JSON.stringify({"suite":"owner-prediction","checks":checks,"failures":failures,
		"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
