extends SceneTree
## Drives shipped UI/direct sockets. Files coordinate actions, never world facts.
var client: Node
var options: Dictionary = {}
var failures: Array[String] = []
var checks := 0
var sequence := 0
var busy := true
var finished := false
var deadline := 0
var evidence: Array = []
var old_channel: RefCounted
var states: Array[String] = []
var ready_count := 0
var instance_id := 0

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

func wait_state(value: String) -> void:
	while not finished and client.state != value:
		if value == "READY" and client.state == "FAILED": break
		await process_frame
	check(not finished and client.state == value, "STATE_" + value)

func wait_scene(value: String) -> void:
	while not finished and (current_scene == null or current_scene.name != value or not current_scene.is_node_ready()):
		await process_frame
	await process_frame

func start() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		if parts.size() == 2: options[parts[0]] = parts[1]
	client = root.get_node("MmoClient")
	instance_id = client.get_instance_id()
	client.request_timeout_ms = 1200
	client.connect_timeout_ms = 1200
	client.state_changed.connect(on_state)
	client.world_ready.connect(func(): ready_count += 1)
	deadline = Time.get_ticks_msec() + 110000
	change_scene_to_file("res://scenes/mmo/login.tscn")
	await wait_scene("Login")
	write_reply(0,{"state":client.state})
	busy = false

func on_state(value: String) -> void:
	states.append(value)
	if value == "FAILED" and current_scene != null and current_scene.name == "World":
		var platform: Node = current_scene.platform
		check(platform._suspended and not current_scene.prediction.view().active, "FAILURE_FREEZES_AND_CLEARS_PREDICTION_SYNCHRONOUSLY")
		var local_x: float = platform.sprite.position.x
		var local_frame: int = platform.sprite.frame
		var camera_x: float = platform.camera.position.x
		var remote: Dictionary = {}
		for id in platform.remote_players:
			var node: Node = platform.remote_players[id]
			remote[id] = [node.position.x,node.sprite.frame]
		for i in range(1000):
			platform._process(10)
			for node in platform.remote_players.values(): node._process(10)
		check(platform.sprite.position.x == local_x and platform.sprite.frame == local_frame and platform.camera.position.x == camera_x, "LOCAL_STALE_NOT_SIMULATED")
		for id in remote:
			var node: Node = platform.remote_players[id]
			check(node.suspended and node.position.x == remote[id][0] and node.sprite.frame == remote[id][1], "REMOTE_STALE_NOT_SIMULATED")

func write_reply(number: int, value: Dictionary) -> void:
	var path: String = options.control.path_join(str(number) + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)

func inspect(command: Dictionary) -> Dictionary:
	await create_timer(.3).timeout
	var view: Dictionary = client.world_replica.view()
	check(client.state == "READY" and view.status == "SYNCED" and not view.reconnect_required, "FRESH_HEALTHY_WORLD")
	check(current_scene.name == "World" and client.get_instance_id() == instance_id, "PERSISTENT_CORE_FRESH_SCENE")
	var world: Control = current_scene
	check(not world.platform._suspended and not world.prediction.view().active, "READY_PRESENTATION")
	check(world.platform.remote_players.size() == view.players.size() - 1, "MEMBERSHIP_REPLACED")
	check(world.platform.sprite.position.x == world.platform.server_to_pixel(view.confirmed_local_x), "CONFIRMED_PROJECTION")
	if command.has("x"): check(view.confirmed_local_x == command.x,"EXPECTED_X")
	if command.has("version"): check(view.map.content_version == command.version,"EXPECTED_MAP_VERSION")
	var value := {"state":client.state,"epoch":view.epoch,"revision":view.revision,"x":view.confirmed_local_x,"map":view.map,"map_source":client.map_source,"population":view.players.size(),"world_ready_count":ready_count}
	return value

func execute(command: Dictionary) -> void:
	var value: Dictionary = {}
	match command.action:
		"connect":
			await wait_scene("Login")
			var login: Control = current_scene
			if command.get("initial",false):
				login.host.text = "127.0.0.1"
				login.port.value = int(options.port)
				login.port.get_line_edit().text = options.port
				login.nickname.text = "player1"
			else:
				check(login.host.text == "127.0.0.1" and login.port.value == int(options.port) and login.nickname.text == "player1", "ENDPOINT_RETAINED_IN_MEMORY")
				check(login.connect_button.text == "Reconnect", "EXPLICIT_RECONNECT_CONTROL")
			if client.state == "FAILED": check(not client.request_state() and not client.set_input("right"),"FENCED_NO_STATE_REPAIR_OR_MUTATION")
			login.connect_button.pressed.emit()
			login.connect_button.pressed.emit()
			await wait_state(command.get("expect","READY"))
			if client.state == "READY":
				await wait_scene("World")
				value = await inspect(command)
			else: value = {"state":client.state,"fault":client.last_error.duplicate()}
		"move":
			await create_timer(.1).timeout
			var adapter: Node = current_scene.input_adapter
			var before_x: int = client.world_replica.view().confirmed_local_x
			adapter._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
			key(false)
			adapter._process(0)
			key(true)
			adapter._process(0)
			check(client.state == "MOVING", "FRESH_EXPLICIT_HUMAN_INPUT")
			while client.state != "FAILED" and client.world_replica.view().confirmed_local_x == before_x:
				await process_frame
			key(false)
			adapter._process(0)
			if client.state != "FAILED":
				await wait_state(command.get("expect","READY"))
			else:
				check(command.get("expect","READY") == "FAILED", "EXPECTED_INPUT_FAILURE")
			if client.state == "READY": value = await inspect(command)
		"refresh":
			current_scene.refresh_button.pressed.emit()
			check(client.state == "RESYNCING", "EXPLICIT_STATE_RESYNC")
			await wait_state(command.get("expect","READY"))
			if client.state == "READY": value = await inspect(command)
		"remember_channel": old_channel = client._channel
		"old_callbacks":
			var before: Dictionary = client.world_replica.view()
			var state_before: String = client.state
			# Closed transport callback regression only; never injects a live fact.
			old_channel.failed.emit("DISCONNECTED")
			old_channel.connected.emit()
			old_channel.frame_received.emit("{}".to_utf8_buffer())
			check(client.state == state_before and client.world_replica.view() == before, "CLOSED_GENERATION_CALLBACKS_IGNORED")
		"hold": key(true)
		"release": key(false)
		"no_replay":
			var before: Dictionary = client.world_replica.snapshot()
			current_scene.input_adapter._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
			await create_timer(.7).timeout
			check(client.state == "READY" and client.world_replica.snapshot() == before, "HELD_KEY_CANNOT_REPLAY_AFTER_RECONNECT")
			value = await inspect(command)
		"fault":
			await wait_state("FAILED")
			await wait_scene("Login")
			check(client.last_error.code == command.code, "FAULT_CODE")
			if command.code == "INVALID_MAP": check(current_scene.status_label.text.contains("incompatible"), "MAP_MIGRATION_ERROR_VISIBLE")
			check(client.last_error.outcome_unknown == command.get("unknown",false), "UNKNOWN_OUTCOME_SEMANTICS")
			var view: Dictionary = client.world_replica.view()
			if command.has("reason"): check(view.stale_reason == command.reason,"STALE_REASON")
			if command.has("x"): check(view.confirmed_local_x == command.x,"LAST_CONFIRMED_FACT_PRESERVED")
			check(client.session_id.is_empty() and client._ticket.is_empty() and client._pending.is_empty() and client._scheduled.is_empty(), "FENCED_CREDENTIALS_AND_QUEUE_CLEARED")
			check(not current_scene.connect_button.disabled and current_scene.cancel_button.disabled, "RETRY_ENABLED")
			check(current_scene.status_label.text.contains("Server outcome unknown") == command.get("unknown",false), "VISIBLE_UNKNOWN_OUTCOME")
			await create_timer(.4).timeout
			check(client.state == "FAILED", "NO_AUTOMATIC_RECONNECT")
			value = {"fault":client.last_error.duplicate(),"replica":view}
		"inspect": value = await inspect(command)
		"logout":
			current_scene.leave_button.pressed.emit()
			await wait_state(command.get("expect","DISCONNECTED"))
			await wait_scene("Login")
		"finish":
			key(false)
			client.disconnect_world()
			finished = true
			print(JSON.stringify({"suite":"recovery","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"states":states,"evidence":evidence}))
			quit(0 if failures.is_empty() else 1)
	if command.has("capture"):
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(command.capture) == OK,"SCREENSHOT")
	value["failures"] = failures.duplicate()
	evidence.append({"sequence":sequence,"action":command.action,"value":value})
	write_reply(sequence,value)
	busy = false

func _process(_delta: float) -> bool:
	if finished: return false
	if deadline != 0 and Time.get_ticks_msec() >= deadline:
		check(false,"OVERALL_TIMEOUT")
		print(JSON.stringify({"suite":"recovery","result":"FAIL","failures":failures}))
		finished = true
		quit(1)
	if busy or options.is_empty(): return false
	var path: String = options.control.path_join("command.json")
	if not FileAccess.file_exists(path): return false
	var command: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if command is Dictionary and command.sequence > sequence:
		sequence = command.sequence
		busy = true
		execute.call_deferred(command)
	return false
