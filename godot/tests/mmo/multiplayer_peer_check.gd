extends SceneTree
## Test driver only. Files coordinate two independent shipped Godot clients.
var client: Node
var options: Dictionary = {}
var checks := 0
var failures: Array[String] = []
var evidence: Array = []
var events: Dictionary = {"joined":0,"moved":0,"left":0}
var sequence := 0
var busy := false
var finished := false
var deadline := 0

func _initialize() -> void:
	start.call_deferred()

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures.append(reason)

func write_reply(number: int, value: Dictionary) -> void:
	var path: String = options.control.path_join(options.nickname + "-" + str(number) + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)

func wait_state(value: String) -> void:
	while not finished and client.state != value and client.state != "FAILED":
		await process_frame
	check(not finished and client.state == value, "STATE_" + value)

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func human_step(direction: String) -> void:
	var adapter: Node = current_scene.input_adapter
	var before_x: int = client.world_replica.view().confirmed_local_x
	# Two windows cannot both own desktop focus. Explicit test focus + release
	# exercise the shipped InputAdapter, without changing product focus behavior.
	adapter._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	key(KEY_A,false)
	key(KEY_D,false)
	adapter._process(0)
	var code := KEY_A if direction == "left" else KEY_D
	key(code,true)
	adapter._process(0)
	check(client.state == "MOVING", "A_D_HELD_INPUT_SCHEDULED")
	while not finished and client.state != "FAILED" and client.world_replica.view().confirmed_local_x == before_x:
		await process_frame
	key(code,false)
	adapter._process(0)
	await wait_state("READY")

func enter() -> void:
	check(client.connect_world("127.0.0.1", int(options.port), options.nickname), "CONNECT")
	await wait_state("READY")
	if client.state != "READY": return
	check(change_scene_to_file("res://scenes/mmo/world.tscn") == OK, "WORLD_SCENE")
	await process_frame
	await process_frame

func start() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() == 2: options[parts[0]] = parts[1]
	client = root.get_node("MmoClient")
	client.event_received.connect(func(value: Dictionary): events[value.event] += 1)
	deadline = Time.get_ticks_msec() + 90000
	busy = true
	await enter()
	write_reply(0, {"ready":client.state == "READY","player_id":client.player_id})
	busy = false

func inspect(command: Dictionary) -> Dictionary:
	# Let the last interpolation finish; commands never inject world facts.
	await create_timer(.25).timeout
	var world: Control = current_scene
	var view: Dictionary = client.world_replica.view()
	check(client.state == "READY" and view.status == "SYNCED", "HEALTHY_STREAM")
	check(world.platform.remote_players.size() == view.players.size() - 1, "PROJECTION_MEMBERSHIP")
	check(world.platform.local_label.text == options.nickname + " (you)", "LOCAL_LABEL")
	var shown: Dictionary = {}
	for id in view.players:
		var player: Dictionary = view.players[id]
		var x: float = world.platform.sprite.position.x if id == client.player_id else world.platform.remote_players[id].position.x
		check(is_equal_approx(x,world.platform.server_to_pixel(player.x)), "CONFIRMED_DISPLAY_" + player.nickname)
		if id != client.player_id:
			var remote: Node2D = world.platform.remote_players[id]
			check(remote.identity.text == player.nickname and remote.sprite.get_script() == null and remote.get_child_count() == 2, "REMOTE_PRESENTATION_ONLY")
		shown[player.nickname] = {"x":player.x,"pixel_x":x,"local":id == client.player_id}
	for nickname in command.get("positions", {}):
		check(shown.has(nickname) and shown[nickname].x == command.positions[nickname], "EXPECTED_POSITION_" + nickname)
	check(shown.size() == command.get("population", shown.size()), "EXPECTED_POPULATION")
	if command.has("capture"):
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(command.capture) == OK, "SCREENSHOT")
	return {"players":shown,"epoch":view.epoch,"revision":view.revision,"events":events.duplicate(),"local_id":client.player_id}

func execute(command: Dictionary) -> void:
	var value: Dictionary = {}
	match command.action:
		"inspect": value = await inspect(command)
		"move":
			for i in range(command.get("count",1)):
				await create_timer(.22).timeout
				await human_step(command.direction)
			value = await inspect(command)
		"logout":
			check(client.logout(), "LOGOUT")
			await wait_state("DISCONNECTED")
			await process_frame
			value = {"state":client.state}
		"enter":
			await enter()
			value = await inspect(command)
		"refresh":
			check(client.request_state(), "STATE_REQUEST")
			await wait_state("READY")
			value = await inspect(command)
		"finish":
			if client.state == "READY":
				check(client.logout(), "FINAL_LOGOUT")
				await wait_state("DISCONNECTED")
			finish()
	value["failures"] = failures.duplicate()
	evidence.append({"sequence":sequence,"action":command.action,"value":value})
	write_reply(sequence,value)
	busy = false

func _process(_delta: float) -> bool:
	if not finished and deadline != 0 and Time.get_ticks_msec() >= deadline:
		check(false,"OVERALL_TIMEOUT")
		finish()
	if finished or busy or options.is_empty(): return false
	var path: String = options.control.path_join(options.nickname + "-command.json")
	if not FileAccess.file_exists(path): return false
	var command: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if command is Dictionary and command.sequence > sequence:
		sequence = command.sequence
		busy = true
		execute.call_deferred(command)
	return false

func finish() -> void:
	if finished: return
	finished = true
	client.disconnect_world()
	print(JSON.stringify({"suite":"multiplayer","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"evidence":evidence,"input_driver":"Synthetic A/D through shipped InputAdapter; explicit test focus/release per step for two simultaneous windows."}))
	quit(0 if failures.is_empty() else 1)
