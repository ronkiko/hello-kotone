extends SceneTree
var client: Node
var options: Dictionary = {}
var failures: Array[String] = []
var checks := 0
var input_receipts := 0
var own_events := 0
var finished := false
var deadline := 0
var evidence: Dictionary = {}

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
		if op == "input": input_receipts += 1)
	client.event_received.connect(func(event: Dictionary):
		if event.event == "moved" and event.data.player.player_id == client.player_id:
			own_events += 1
			check(client.world_replica.local_player().x == event.data.player.x, "EVENT_APPLIED_BEFORE_SIGNAL"))
	deadline = Time.get_ticks_msec() + 65000
	check(not client.set_input("right"), "NO_INPUT_BEFORE_READY")
	check(client.connect_world("127.0.0.1", int(options.port), "player1"), "CONNECT")
	await wait_state("READY")
	if finished or client.state != "READY": return
	change_scene_to_file("res://scenes/mmo/world.tscn")
	await process_frame
	await process_frame
	await real_wall()
	finish()

func hold_to_confirmed(code: int, target: int) -> void:
	var world: Control = current_scene
	key(KEY_A,false); key(KEY_D,false)
	world.input_adapter._process(0)
	key(code,true)
	world.input_adapter._process(0)
	check(world.input_adapter.locomotion_intent != 0 and client.state == "MOVING", "HELD_INPUT_SCHEDULED")
	while not finished and client.state != "FAILED" and client.world_replica.local_player().x != target:
		await process_frame
	key(code,false)
	world.input_adapter._process(0)
	await wait_state("READY")
	await settle()

func real_wall() -> void:
	var world: Control = current_scene
	var session: String = client.session_id
	check(client.world_replica.local_player().x == 50, "REAL_SPAWN")
	await capture("spawn")

	var before_events := own_events
	await hold_to_confirmed(KEY_A, 0)
	if finished: return
	check(client.world_replica.local_player().x == 0, "LEFT_WALL_CONFIRMED")
	check(input_receipts == 2, "LEFT_PRESS_STOP_ONLY_TWO_INPUT_REQUESTS")
	check(own_events - before_events >= 50 and own_events - before_events <= 51, "SERVER_CADENCE_OWNS_LEFT_STEPS")
	check(client.session_id == session, "LEFT_SESSION_UNCHANGED")
	check(is_equal_approx(world.platform.character_root.position.x, world.platform.server_to_pixel(0)), "LEFT_RENDER_CONVERGED")
	check(world.platform.sprite.animation == &"idle", "LEFT_RELEASE_FRONT_IDLE")
	await capture("left-wall")

	before_events = own_events
	await hold_to_confirmed(KEY_D, 100)
	if finished: return
	check(client.world_replica.local_player().x == 100, "RIGHT_WALL_CONFIRMED")
	check(input_receipts == 4, "FULL_TRAVERSE_FOUR_INPUT_STATE_REQUESTS")
	check(own_events - before_events >= 100 and own_events - before_events <= 101, "SERVER_CADENCE_OWNS_RIGHT_STEPS")
	check(client.session_id == session, "RIGHT_SESSION_UNCHANGED")
	check(is_equal_approx(world.platform.character_root.position.x, world.platform.server_to_pixel(100)), "RIGHT_RENDER_CONVERGED")
	check(world.platform.sprite.animation == &"idle", "RIGHT_RELEASE_FRONT_IDLE")
	await capture("right-wall")

	world.platform.character_root.position.x = -10000
	check(client.world_replica.local_player().x == 100, "SPRITE_TAMPER_NO_SERVER_WRITE")
	world.platform._process(0)
	check(world.platform.character_root.position.x == world.platform.trajectory.visual_x, "SPRITE_TAMPER_REPAIRED_FROM_LOCAL_MODEL")
	world.refresh_button.pressed.emit()
	await wait_state("READY")
	await settle()
	check(current_scene == world and client.world_replica.local_player().x == 100, "STATE_PRESERVES_SERVER_TRUTH")
	check(is_equal_approx(world.platform.character_root.position.x, world.platform.server_to_pixel(100)), "STATE_RECONCILES_PRESENTATION")
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
