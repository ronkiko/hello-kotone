extends SceneTree
var client: Node
var options: Dictionary = {}
var checks := 0
var failures: Array[String] = []
var input_acks := 0
var facts := 0
var finished := false
var deadline := 0

func _initialize() -> void:
	start.call_deferred()

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures.append(reason)

func key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_D
	event.physical_keycode = KEY_D
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func wait_ready_or_failed() -> void:
	while client.state not in ["READY","FAILED"]:
		await process_frame

func start() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=",true,1)
		if parts.size() == 2: options[parts[0]] = parts[1]
	client = root.get_node("MmoClient")
	client.request_timeout_ms = 1000 if options.mode == "lost_reply" else 5000
	client.input_accepted.connect(func(_seq: int, _direction: String, _x: int): input_acks += 1)
	client.world_replica.local_moved.connect(func(_event: Dictionary, _previous_x: int): facts += 1)
	deadline = Time.get_ticks_msec() + 12000
	check(client.connect_world("127.0.0.1",int(options.port),"player1"), "CONNECT")
	await wait_ready_or_failed()
	if client.state != "READY": finish(); return
	change_scene_to_file("res://scenes/mmo/world.tscn")
	await process_frame
	await process_frame
	var world: Control = current_scene
	var start_px: float = world.platform.sprite.position.x
	var confirmed: int = client.world_replica.local_player().x

	# Satisfy the fresh-world release gate, then start locally immediately.
	key(false); world.input_adapter._process(0)
	key(true); world.input_adapter._process(0)
	check(world.input_adapter.locomotion_intent == 1 and client.state == "MOVING", "HELD_INPUT_ADMITTED_LOCALLY")
	await create_timer(.15).timeout
	check(client.world_replica.local_player().x == confirmed and input_acks == 0, "SERVER_ACK_STILL_DELAYED")
	check(world.platform.sprite.position.x > start_px and world.platform.trajectory.model_x > start_px,
		"LOCAL_RENDER_MOVES_WITHOUT_SERVER_ACK")
	check(client.world_replica.local_player().x == confirmed, "PREDICTION_NEVER_WRITES_REPLICA")

	if options.mode == "rapid_release":
		key(false); world.input_adapter._process(0)
		check(world.input_adapter.locomotion_intent == 0, "RELEASE_BEFORE_ACK_STOPS_LOCAL_SIMULATION")
	if options.mode == "lost_reply":
		await wait_ready_or_failed()
		check(client.state == "FAILED" and client.last_error.operation == "input" and client.last_error.outcome_unknown,
			"LOST_INPUT_REPLY_IS_UNKNOWN_OUTCOME")
		check(client.world_replica.view().status == "STALE" and client.world_replica.view().reconnect_required,
			"UNKNOWN_OUTCOME_FENCES_REPLICA_NO_REPLAY")
		finish()
		return

	while input_acks < 1 and client.state != "FAILED":
		await process_frame
	check(input_acks >= 1, "RIGHT_INPUT_ACK")
	if options.mode == "rapid_release":
		while input_acks < 2 and client.state != "FAILED":
			await process_frame
		await create_timer(.25).timeout
		check(facts == 0 and client.world_replica.local_player().x == confirmed, "COALESCED_STOP_BEATS_FIRST_SERVER_TICK")
		check(world.platform.trajectory.intent == 0, "NO_HIDDEN_HELD_INTENT_AFTER_COALESCED_STOP")
	else:
		while facts < 2 and client.state != "FAILED":
			await process_frame
		if options.mode == "match":
			check(client.world_replica.local_player().x == confirmed + 2, "MATCHED_SERVER_FACTS_ADVANCE_CONFIRMED")
			check(world.platform.trajectory.model_x >= world.platform.server_to_pixel(confirmed + 2),
				"MATCHED_FACTS_DO_NOT_REWIND_CONTINUOUS_PREDICTION")
		else:
			check(options.mode == "hold" and client.world_replica.local_player().x == confirmed, "SERVER_HOLD_KEEPS_CONFIRMED_X")
			check(world.platform.trajectory.model_x < start_px + 16.0, "HOLD_FACTS_PULL_PREDICTED_MODEL_BACK")
		key(false); world.input_adapter._process(0)
		while input_acks < 2 and client.state != "FAILED":
			await process_frame

	await create_timer(.5).timeout
	check(world.input_adapter.locomotion_intent == 0 and world.platform.trajectory.intent == 0, "RELEASE_IS_STABLE_STOP")
	check(is_equal_approx(world.platform.sprite.position.x, world.platform.server_to_pixel(client.world_replica.local_player().x)),
		"FINAL_RENDER_CONVERGES_TO_AUTHORITATIVE_X")
	check(world.platform.sprite.texture == world.platform.IDLE, "FINAL_STOP_RETURNS_FRONT_IDLE")
	check(client.state == "READY", "SESSION_STAYS_HEALTHY")
	check(client.logout(), "LOGOUT")
	while client.state != "DISCONNECTED": await process_frame
	finish()

func _process(_delta: float) -> bool:
	if not finished and deadline != 0 and Time.get_ticks_msec() >= deadline:
		check(false,"OVERALL_TIMEOUT")
		finish()
	return false

func finish() -> void:
	if finished: return
	finished = true
	key(false)
	if client != null and client.state not in ["IDLE","DISCONNECTED"]: client.disconnect_world()
	print(JSON.stringify({"suite":"prediction","result":"PASS" if failures.is_empty() else "FAIL",
		"checks":checks,"failures":failures,"input_acks":input_acks,"facts":facts}))
	quit(0 if failures.is_empty() else 1)
