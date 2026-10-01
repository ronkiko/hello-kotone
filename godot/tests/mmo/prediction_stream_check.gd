extends SceneTree
var client: Node
var options: Dictionary = {}
var checks := 0
var failures: Array[String] = []
var model: RefCounted
var facts := 0
var receipts := 0
var intentions := 0
var rejections: Array[String] = []
var fault_projection: Dictionary = {}
var evidence: Dictionary = {}
var deadline := 0
var finished := false

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

func world_scene() -> Control:
	change_scene_to_file("res://scenes/mmo/world.tscn")
	await process_frame
	await process_frame
	return current_scene

func capture(world: Control, name: String) -> void:
	if not options.has("capture"): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(options.capture.path_join(name + ".png")) == OK, "CAPTURE_" + name)
	evidence[name] = {"model":model.view(),"render_pixel_x":world.platform.sprite.position.x,"label":world.position_label.text}

func start() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=",true,1)
		if parts.size() == 2: options[parts[0]] = parts[1]
	client = root.get_node("MmoClient")
	var mode: String = options.mode
	deadline = Time.get_ticks_msec() + 15000
	client.request_timeout_ms = 1100 if mode == "timeout" else 5000
	client.move_intended.connect(func(_direction: String): intentions += 1)
	client.world_replica.local_moved.connect(func(): facts += 1)
	client.response_received.connect(func(op: String, _data: Dictionary):
		if op == "move": receipts += 1)
	client.move_rejected.connect(func(code: String): rejections.append(code))
	client.fault.connect(func(_info: Dictionary):
		if model != null: fault_projection = model.view())
	check(client.connect_world("127.0.0.1",int(options.port),"player1"), "CONNECT")
	await wait_state("READY")
	if client.state != "READY": finish(); return
	var world: Control = await world_scene()
	model = world.prediction
	var baseline: Dictionary = client.world_replica.snapshot()
	var x: int = client.world_replica.local_player().x
	var direction: String = options.get("direction","right")
	var predicted := clampi(x + (-1 if direction == "left" else 1),client.map_document.min_x,client.map_document.max_x)
	var start_px: float = world.platform.server_to_pixel(x)
	var predicted_px: float = world.platform.server_to_pixel(predicted)
	if mode == "cancel_before_send":
		client.state_changed.connect(func(value: String):
			if value == "MOVING": client.disconnect_world())
		check(not client.move(direction), "SYNCHRONOUS_UNSENT_CANCELLATION")
		check(client.state == "DISCONNECTED" and intentions == 0 and model.view().target_x == null, "UNSENT_NOT_SPECULATED_OR_UNKNOWN")
		await create_timer(.3).timeout
		finish()
		return
	if mode == "cancel_after_fact":
		client.world_replica.local_moved.connect(client.disconnect_world)
	var code := KEY_LEFT if direction == "left" else KEY_RIGHT
	key(code,false)
	world.input_adapter._process(0)
	key(code,true)
	world.input_adapter._process(0)
	check(client.state == "MOVING" and intentions == 1, "INPUT_ACCEPTED_ONE_INTENTION")
	check(model.view().active and model.view().predicted_x == predicted and model.view().confirmed_x == x and client.world_replica.snapshot() == baseline, "IMMEDIATE_PREDICTION_WITHOUT_FACT_WRITE")
	check(not client.move("left") and not client.request_state() and not client.logout(), "NO_SECOND_REQUEST_WHILE_SPECULATING")
	for i in range(1000): world.input_adapter._process(1)
	check(intentions == 1 and model.view().predicted_x == predicted, "HELD_INPUT_NO_PREDICTION_BACKLOG")
	await create_timer(.12).timeout
	check(client.world_replica.local_player().x == x and facts == 0 and receipts == 0, "LATENCY_CONFIRMED_UNCHANGED")
	check(is_equal_approx(world.platform.sprite.position.x,predicted_px), "RENDER_REACHES_PREDICTED_BEFORE_FACT")
	world.platform.sprite.position.x = -99999
	world.platform._process(0)
	check(is_equal_approx(world.platform.sprite.position.x,predicted_px) and client.world_replica.local_player().x == x, "TAMPER_NOT_AUTHORITY")
	await capture(world,"predicted")
	var rejected := mode in ["out_of_bounds","rate_limited","world_paused","left_bound","right_bound"]
	if not rejected:
		key(code,false)
		world.input_adapter._process(0)
		key(KEY_A,true)
		for i in range(100): world.input_adapter._process(1)
		key(KEY_A,false)
		world.input_adapter._process(0)
		check(intentions == 1 and model.view().target_x == predicted, "RELEASE_AND_REVERSAL_DO_NOT_REPLAY_OR_RETRACT_STEP")
	if mode == "remote_interleaving":
		await create_timer(.2).timeout
		check(client.world_replica.snapshot().revision == 2 and model.view().active and client.world_replica.local_player().x == x, "REMOTE_FACT_DOES_NOT_CLEAR_LOCAL_PREDICTION")
	if mode == "fact_before_receipt":
		await create_timer(.2).timeout
		check(client.state == "MOVING" and facts == 1 and receipts == 0 and not model.view().active and model.view().target_x == predicted, "OWN_FACT_CLEARS_PREDICTION_BEFORE_RECEIPT")
		check(not client.move("left"), "FACT_DOES_NOT_OPEN_REQUEST_SLOT")
	if options.has("expect"):
		await wait_state("FAILED")
		var expected_x := int(options.get("confirmed",str(x)))
		check(client.last_error.code == options.expect and client.last_error.outcome_unknown, "EXPECTED_UNKNOWN_FENCED_OUTCOME")
		check(client.world_replica.view().status == "STALE" and client.world_replica.view().reconnect_required and client.session_id.is_empty(), "STALE_REQUIRES_FRESH_ENTER")
		check(client.world_replica.local_player().x == expected_x and not fault_projection.active and fault_projection.predicted_x == null and fault_projection.target_x == expected_x, "FAULT_REMOVES_SPECULATION_RETAINS_LAST_FACT")
		check(not client.move("right") and not client.request_state(), "NO_REPLAY_NO_STATE_REPAIR")
		evidence["failure"] = {"fault":client.last_error.duplicate(),"projection":fault_projection,"replica":client.world_replica.view()}
		await create_timer(.3).timeout
		if mode == "fresh_epoch":
			check(client.connect_world("127.0.0.1",int(options.port),"player1"), "EXPLICIT_FRESH_LOGIN")
			await wait_state("READY")
			world = await world_scene()
			model = world.prediction
			check(client.world_replica.view().epoch == "e2" and model.view().target_x == 20 and not model.view().active and intentions == 1, "NEW_EPOCH_NO_OLD_SPECULATION_OR_REPLAY")
			check(client.move("left"), "FRESH_DIFFERENT_INTENTION")
			await wait_state("READY")
			check(client.world_replica.local_player().x == 19 and receipts == 1 and intentions == 2, "FRESH_BASELINE_CONFIRMED")
			check(client.logout(), "FRESH_LOGOUT")
			await wait_state("DISCONNECTED")
	else:
		await wait_state("READY")
		if rejected:
			check(rejections == [options.code] and client.world_replica.snapshot() == baseline and receipts == 0 and facts == 0, "REJECTION_NO_PHYSICAL_STEP")
			check(not model.view().active and model.view().target_x == x, "REJECTION_TARGET_CONFIRMED")
			await create_timer(.35).timeout
			check(intentions == 1 and rejections.size() == 1, "REJECTED_HOLD_NO_AUTORETRY")
			key(code,false)
			world.input_adapter._process(0)
			check(is_equal_approx(world.platform.sprite.position.x,start_px), "BOUNDED_ROLLBACK_COMPLETES")
			await capture(world,"rollback")
		else:
			var expected_x := x if mode == "unchanged_fact" else (x - 1 if mode == "server_correction" else predicted)
			check(client.world_replica.local_player().x == expected_x and facts == 1 and receipts == 1, "ONE_FACT_ONE_RECEIPT")
			check(not model.view().active and model.view().target_x == expected_x, "FACT_RECONCILES_PREDICTION")
			await create_timer(.12).timeout
			check(is_equal_approx(world.platform.sprite.position.x,world.platform.server_to_pixel(expected_x)), "CORRECTION_OR_CONFIRMATION_RENDERED")
			await capture(world,"confirmed")
		check(client.request_state(), "HEALTHY_REFRESH")
		await wait_state("READY")
		check(not model.view().active and model.view().target_x == client.world_replica.local_player().x, "STATE_DOES_NOT_RESURRECT_PREDICTION")
		await create_timer(.25).timeout
		check(intentions == 1, "RELEASED_INPUT_NO_LATER_REPLAY")
		check(client.logout(), "LOGOUT")
		await wait_state("DISCONNECTED")
	evidence["counts"] = {"intentions":intentions,"facts":facts,"receipts":receipts,"rejections":rejections}
	finish()

func _process(_delta: float) -> bool:
	if not finished and deadline != 0 and Time.get_ticks_msec() >= deadline:
		check(false,"OVERALL_TIMEOUT")
		finish()
	return false

func finish() -> void:
	if finished: return
	finished = true
	for code in [KEY_LEFT,KEY_RIGHT,KEY_A]: key(code,false)
	if client != null: client.disconnect_world()
	print(JSON.stringify({"suite":"prediction","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"evidence":evidence}))
	quit(0 if failures.is_empty() else 1)
