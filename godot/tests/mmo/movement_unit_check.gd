extends SceneTree
const Protocol = preload("res://scripts/mmo/protocol_v7.gd")
const Adapter = preload("res://scripts/ui/move_input.gd")
const Platform = preload("res://scripts/presentation/platform_world.gd")
var failures: Array[String] = []
var checks := 0

class FakeClient extends Node:
	signal input_rejected(code: String)
	signal state_changed(state: String)
	var state := "READY"
	var inputs: Array[String] = []
	func set_input(direction: String) -> bool:
		if state not in ["READY","MOVING"]: return false
		inputs.append(direction)
		return true

func _initialize() -> void:
	start.call_deferred()

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures.append(reason)

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func start() -> void:
	var input_reply := {"protocol_version":7,"type":"response","request_id":"r1","op":"input","status":"ok",
		"data":{"epoch":"e1","zone_id":"city/apartment","player_id":"p1","input_seq":1,"x":50},"error":null}
	check(Protocol.response(input_reply), "INPUT_RESPONSE_SCHEMA")
	var client := FakeClient.new()
	root.add_child(client)
	var adapter := Adapter.new()
	adapter.client = client
	var changes: Array[int] = []
	adapter.locomotion_intent_changed.connect(func(value: int): changes.append(value))
	root.add_child(adapter)
	adapter.set_process(false)

	key(KEY_D,true)
	adapter._process(0)
	check(client.inputs.is_empty() and adapter.locomotion_intent == 0, "FRESH_WORLD_REQUIRES_RELEASE")
	key(KEY_D,false); adapter._process(0)
	key(KEY_D,true); adapter._process(0)
	check(client.inputs == ["right"] and adapter.locomotion_intent == 1 and changes == [1], "PRESS_SENDS_ONE_HELD_INPUT")
	for i in range(1000): adapter._process(1)
	check(client.inputs == ["right"], "HOLD_HAS_NO_REQUEST_BACKLOG")
	key(KEY_D,false); adapter._process(0)
	check(client.inputs == ["right","stop"] and adapter.locomotion_intent == 0 and changes.back() == 0, "RELEASE_SENDS_STOP_ONCE")
	key(KEY_A,true); adapter._process(0)
	check(client.inputs.back() == "left" and adapter.locomotion_intent == -1, "REVERSAL_IS_INPUT_STATE_CHANGE")
	client.input_rejected.emit("WORLD_PAUSED")
	check(adapter.locomotion_intent == 0 and client.inputs.back() == "stop", "REJECTION_FORCES_LOCAL_AND_SERVER_STOP")
	key(KEY_A,false); adapter._process(0)
	client.state = "RESYNCING"
	client.state_changed.emit("RESYNCING")
	adapter._process(0)
	var inputs_before_loading := client.inputs.size()
	key(KEY_D,true); adapter._process(0)
	check(adapter.locomotion_intent == 0 and client.inputs.size() == inputs_before_loading, "NONINTERACTIVE_STATE_CANNOT_START_LOCAL_DRIFT")
	key(KEY_D,false); adapter._process(0)
	client.state = "READY"

	var viewport := SubViewport.new()
	viewport.size = Vector2i(458,116)
	root.add_child(viewport)
	var platform := Platform.new()
	check(platform.set_movement_rules({"movement":{"step_units":1,"min_move_interval_ms":200}}), "MOVEMENT_RULES")
	viewport.add_child(platform)
	platform.set_process(false)
	var map := {"schema_version":1,"map_id":"city/apartment","content_version":1,"min_x":0,"max_x":100,"spawn_x":50,
		"units_per_meter":1,"content_hash":"4f465435cbb8eb3e5154a4776be29e7aee4f73376e00fb26299bfbf0cfcd361b"}
	var view := {"map":{"map_id":map.map_id,"content_version":1,"content_hash":map.content_hash},
		"confirmed_local_x":50,"epoch":"e1","local_player_id":"p1",
		"players":{"p1":{"player_id":"p1","nickname":"player1","zone_id":"city/apartment","x":50}}}
	check(platform.project(map,view) and platform.sprite.position.x == 432, "CONFIRMED_BASELINE")
	check(is_equal_approx(platform.motion_profile.nominal_speed,40.0), "WORLD_CADENCE_IS_LOCAL_PREDICTION_SPEED")
	check(platform.set_local_intent(1), "LOCAL_HELD_RIGHT")
	platform._process(.10)
	check(is_equal_approx(platform.trajectory.model_x,436.0) and is_equal_approx(platform.sprite.position.x,436.0), "LOCAL_MOVES_BEFORE_SERVER_FACT")
	check(view.confirmed_local_x == 50, "LOCAL_PREDICTION_NEVER_WRITES_CONFIRMED_X")
	platform._process(.40)
	check(platform.sprite.position.x > platform.server_to_pixel(51), "LOCAL_PREDICTION_NOT_ONE_STEP_LEASH")

	# Matching authoritative facts update the ruler/replica outside this presenter but need no correction.
	view.confirmed_local_x = 52
	view.players.p1.x = 52
	check(platform.project(map,view), "CONFIRMED_FACT_DOES_NOT_SNAP_RENDER")
	var before_match := platform.sprite.position.x
	platform._process(0)
	check(platform.sprite.position.x == before_match, "MATCHING_SERVER_STREAM_NO_VISUAL_REWIND")

	# Server same-X fact is an authoritative hold: local prediction stops extending,
	# target becomes confirmed X and render returns magnetically.
	var before_correction := platform.sprite.position.x
	platform.set_authoritative_hold(true)
	platform.reconcile_local_to_confirmed()
	check(platform.trajectory.authoritative_hold and platform.trajectory.model_x == platform.server_to_pixel(52), "SERVER_HOLD_REBASES_TO_CONFIRMED")
	platform._process(.02)
	check(platform.sprite.position.x < before_correction and platform.sprite.position.x > platform.trajectory.model_x, "MAGNETIC_RECONCILIATION")
	platform._process(.2)
	check(is_equal_approx(platform.sprite.position.x,platform.trajectory.model_x), "CORRECTION_SETTLES_BOUNDED")
	var held_x := platform.trajectory.model_x
	platform._process(1)
	check(platform.trajectory.model_x == held_x, "HELD_WORLD_STOPS_LOCAL_PREDICTION_DESPITE_KEY_INTENT")
	platform.set_authoritative_hold(false)
	platform._process(.05) # Resume actually moves before release correction.

	# Release stops local simulation immediately; final resting point converges to authoritative X.
	platform.set_local_intent(0)
	platform.reconcile_local_to_confirmed()
	var released_before := platform.sprite.position.x
	platform._process(.02)
	check(platform.sprite.position.x != released_before, "STOP_RECONCILES_TO_SERVER")
	platform._process(1)
	check(is_equal_approx(platform.sprite.position.x,platform.server_to_pixel(52)), "STOP_FINAL_SERVER_X")
	platform._process(0)
	check(platform.sprite.texture == platform.IDLE, "SETTLED_RELEASE_RETURNS_FRONT_IDLE")

	# Bounds remain client-side presentation limits, never authority writes.
	platform.set_local_intent(1)
	platform._process(100)
	check(platform.sprite.position.x == 832 and platform.trajectory.model_x == 832, "LOCAL_PREDICTION_CLAMPS_MAP_BOUND")
	platform.set_local_intent(0)
	platform.sprite.position.x = -99999
	platform._process(0)
	check(platform.sprite.position.x == platform.trajectory.visual_x, "SPRITE_TAMPER_CANNOT_BECOME_MODEL")

	viewport.queue_free()
	adapter.queue_free()
	client.queue_free()
	print(JSON.stringify({"suite":"movement","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
