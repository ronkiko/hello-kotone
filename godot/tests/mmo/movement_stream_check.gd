extends SceneTree
var client: Node
var options: Dictionary = {}
var failures: Array[String] = []
var checks := 0
var receipts := 0
var input_receipts := 0
var own_events := 0
var rejections: Array[String] = []
var finished := false
var deadline := 0
var evidence: Dictionary = {}
var focus_resumptions := 0

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

func wait_state(value: String) -> void:
	while not finished and client.state != value and client.state != "FAILED":
		await process_frame
	check(not finished and client.state == value, "STATE_" + value)

func settle() -> void:
	await create_timer(float(client.world_rules.movement.min_move_interval_ms) / 1000.0 + 0.08).timeout

func capture(name: String) -> void:
	if not options.has("capture"): return
	await settle()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(options.capture.path_join(name + ".png")) == OK, "CAPTURE_" + name)

func start() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=",true,1)
		if parts.size() == 2: options[parts[0]] = parts[1]
	client = root.get_node("MmoClient")
	client.response_received.connect(func(op: String, _data: Dictionary):
		if op == "move": receipts += 1
		elif op == "input": input_receipts += 1)
	client.event_received.connect(func(event: Dictionary):
		if event.event == "moved" and event.data.player.player_id == client.player_id:
			own_events += 1
			check(client.world_replica.local_player().x == event.data.player.x, "EVENT_APPLIED_BEFORE_SIGNAL")
			if options.get("mode") == "cancel_after_fact":
				client.disconnect_world())
	client.move_rejected.connect(func(code: String): rejections.append(code))
	client.request_timeout_ms = 1000 if options.get("mode") == "timeout" else 20000
	deadline = Time.get_ticks_msec() + (60000 if options.get("mode") == "real_wall" else 12000)
	check(not client.move("right"), "NO_INPUT_BEFORE_READY")
	check(client.connect_world("127.0.0.1", int(options.port), "player1"), "CONNECT")
	if options.get("bootstrap-fault", "false") == "true":
		await wait_state("FAILED")
		check(client.last_error.code == options.expect and client.session_id.is_empty() and not client.move("right"), "RULES_GATE_READY_AND_MOVEMENT")
		finish()
		return
	await wait_state("READY")
	if finished or client.state != "READY": return
	change_scene_to_file("res://scenes/mmo/world.tscn")
	await process_frame
	await process_frame
	check(not client.move("up"), "INVALID_DIRECTION")
	if options.get("mode") == "real_wall":
		await real_wall()
	else:
		await fixture_case()
	finish()

func real_wall() -> void:
	var world: Control = current_scene
	var session: String = client.session_id
	check(client.world_replica.local_player().x == 50, "REAL_SPAWN")
	await capture("spawn")

	key(KEY_A,false); world.input_adapter._process(0)
	key(KEY_A,true); world.input_adapter._process(0)
	check(client.state == "MOVING" and world.input_adapter.locomotion_intent == -1, "LEFT_HELD_INPUT_SENT")
	while not finished and client.state != "FAILED" and client.world_replica.local_player().x > 0:
		await process_frame
	key(KEY_A,false); world.input_adapter._process(0)
	await wait_state("READY")
	await settle()
	if finished: return
	check(client.world_replica.local_player().x == 0, "LEFT_WALL_CONFIRMED")
	check(input_receipts == 2, "LEFT_PRESS_STOP_ONLY_TWO_INPUT_REQUESTS")
	var left_events := own_events
	check(left_events >= 50 and left_events <= 51 and client.session_id == session, "SERVER_CADENCE_OWNS_LEFT_STEPS")
	await capture("left-wall")

	key(KEY_D,true); world.input_adapter._process(0)
	check(client.state == "MOVING" and world.input_adapter.locomotion_intent == 1, "RIGHT_HELD_INPUT_SENT")
	while not finished and client.state != "FAILED" and client.world_replica.local_player().x < 100:
		await process_frame
	key(KEY_D,false); world.input_adapter._process(0)
	await wait_state("READY")
	await settle()
	if finished: return
	check(client.world_replica.local_player().x == 100, "FULL_MIN_TO_MAX")
	check(input_receipts == 4, "FULL_TRAVERSE_FOUR_INPUT_STATE_REQUESTS")
	check(own_events - left_events >= 100 and own_events - left_events <= 101, "SERVER_CADENCE_OWNS_RIGHT_STEPS")
	await capture("right-wall")
	check(is_equal_approx(world.platform.sprite.position.x,832), "VISUAL_RIGHT_BOUNDARY")
	check(world.platform.sprite.texture == world.platform.IDLE, "RELEASE_SETTLES_FRONT_IDLE")

	world.platform.sprite.position.x = -10000
	check(client.world_replica.local_player().x == 100, "SPRITE_TAMPER_NO_SERVER_WRITE")
	world.platform._process(0)
	check(world.platform.sprite.position.x == world.platform.trajectory.visual_x, "SPRITE_TAMPER_REPAIRED_FROM_LOCAL_MODEL")
	world.refresh_button.pressed.emit()
	await wait_state("READY")
	await settle()
	check(current_scene == world and client.world_replica.local_player().x == 100, "STATE_PRESERVES_SERVER_TRUTH")
	await capture("reconciled")
	evidence = {"confirmed_min":0,"confirmed_max":100,"input_state_requests":input_receipts,
		"own_moved_events":own_events,"session_unchanged":client.session_id == session,
		"continuous_local_prediction":true}
	world.leave_button.pressed.emit()
	await wait_state("DISCONNECTED")
	await process_frame
	check(client.connect_world("127.0.0.1",int(options.port),"player1"), "MANUAL_REENTRY_AFTER_FLUSH")
	await wait_state("READY")
	check(client.world_replica.local_player().x == 100, "POSITION_RETAINED_ON_REENTRY")
	check(client.logout(), "REENTRY_LOGOUT")
	await wait_state("DISCONNECTED")

func fixture_case() -> void:
	var mode: String = options.mode
	var world: Control = current_scene
	var session: String = client.session_id
	var rejected: bool = mode in ["out_of_bounds", "rate_limited", "world_paused"]
	check(client.move("right"), "COMPAT_MOVE_SCHEDULED")
	check(not client.move("left") and not client.request_state() and not client.logout(), "ONE_IN_FLIGHT")
	if rejected:
		await wait_state("READY")
		check(rejections == [options.code] and client.session_id == session and client.world_replica.view().status == "SYNCED", "KNOWN_REJECTION_PRESERVES_STREAM")
		check(client.world_replica.local_player().x == 50 and own_events == 0 and receipts == 0, "REJECTION_NO_POSITION_CHANGE")
		check(world.status_label.text.contains(options.text), "VISIBLE_REJECTION")
		await create_timer(0.35).timeout
		check(rejections.size() == 1 and own_events == 0, "HELD_REJECTION_NO_AUTORETRY")
		check(client.move("right"), "COMPAT_MOVE_RETRY")
		await wait_state("READY")
	elif options.has("expect"):
		await wait_state("FAILED")
		key(KEY_D,false)
		var projection: Dictionary = client.world_replica.view()
		check(client.last_error.code == options.expect, "EXPECTED_FAULT")
		check(client.last_error.outcome_unknown == (options.get("unknown","true") == "true"), "MUTATION_OUTCOME_UNKNOWN")
		check(projection.status == "STALE" and projection.reconnect_required and client.session_id.is_empty(), "FAULT_FENCED")
		check(projection.confirmed_local_x == int(options.get("confirmed","50")), "LAST_CONFIRMED_FACT_RETAINED")
		check(not client.move("right") and not client.request_state(), "NO_REPLAY_OR_REPAIR")
		evidence = {"fault":client.last_error.code,"outcome_unknown":client.last_error.outcome_unknown,"confirmed_x":projection.confirmed_local_x,"receipts":receipts,"own_events":own_events}
		return
	else:
		await wait_state("READY")
	if mode == "cadence350":
		var copy: Dictionary = client.world_rules
		copy.movement.min_move_interval_ms = 1
		check(client.world_rules.movement.min_move_interval_ms == 350 and not client.move("right"), "AUTHORITATIVE_CADENCE_NO_LOCAL_200")
	await settle()
	check(receipts == 1 and own_events == 1 and client.world_replica.local_player().x == 51, "FACT_THEN_RECEIPT_ONCE")
	check(is_equal_approx(world.platform.sprite.position.x,440), "CONFIRMED_VISUAL_TARGET")
	await create_timer(0.35).timeout
	check(receipts == 1 and own_events == 1, "NO_RELEASED_INPUT_REPLAY")
	if mode == "cadence350":
		check(client.move("right"), "SERVER_POLICY_BUDGET_OPENS")
		await wait_state("READY")
		check(receipts == 2 and own_events == 2 and client.world_replica.local_player().x == 52, "ALTERNATE_CADENCE_CONFIRMED")
	evidence = {"confirmed_x":client.world_replica.local_player().x,"receipts":receipts,"own_events":own_events,"rejections":rejections}
	check(client.logout(), "FIXTURE_LOGOUT")
	await wait_state("DISCONNECTED")

func _process(_delta: float) -> bool:
	if not finished and deadline != 0 and Time.get_ticks_msec() >= deadline:
		check(false,"OVERALL_TIMEOUT")
		finish()
	return false

func finish() -> void:
	if finished: return
	finished = true
	key(KEY_A,false)
	key(KEY_D,false)
	if client != null: client.disconnect_world()
	print(JSON.stringify({"suite":"movement","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"evidence":evidence}))
	quit(0 if failures.is_empty() else 1)
