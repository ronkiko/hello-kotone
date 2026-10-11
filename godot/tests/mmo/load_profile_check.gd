extends SceneTree
## Actual native Godot TLS client used by 8.12 delay and long-session profiles.

const Appearance = preload("res://scripts/presentation/character_appearance.gd")
var failures: Array[String] = []
var actions := {"intent_to_local_visual_ms": [], "intent_to_local_motion_ms": [],
	"control_send_to_accept_ms": [],
	"accepted_to_owner_sample_ms": [], "input_to_first_owner_sample_ms": [],
	"input_to_applied_control_sample_ms": [],
	"sample_receipt_to_remote_visual_ms": [],
	"input_to_remote_visual_ms": []}
var send_at := {}
var accepted_at := {}
var input_at := {}
var pending_owner_accepts := {}
var superseded_owner_sequences := 0
var remote_onset_times: Array[float] = []
var snapshots: Array[Dictionary] = []
var role := 1
var duration_s := 30
var proxy_port := 0
var output_path := ""
var profile := ""
var pre: Node
var client: Node
var world: Node
var initial_remote_sample_usec := -1
var initial_remote_visual_x := 0.0
var first_motion_sample_usec := -1
var first_motion_visual_x := 0.0
var last_remote_velocity := 0
var current_drive := 0
var current_facing := 1
var approach_direction := 1
var final_owner_metrics: Dictionary = {}
var final_remote_metrics: Dictionary = {}
var sync_file := ""
var synchronized_start_unix := 0.0
var first_input_sync_offset_ms: Variant = null
var intent_started_usec := -1
var intent_initial_x := 0.0
var intent_initial_animation := ""
var intent_visual_recorded := false
var intent_motion_recorded := false
var intent_owner_sample_recorded := false
var short_tap_result: Dictionary = {}
var short_tap_results: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func stage(value: String) -> void:
	print("S812_STAGE ", role, " ", value)
	var file := FileAccess.open(output_path + ".progress", FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()

func wait_until(predicate: Callable, label: String, seconds: float = 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var ok: bool = predicate.call()
	check(ok, label)
	return ok

func distribution(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0,"p50":null,"p95":null,"max":null,"latest":null}
	var ordered: Array = values.duplicate()
	ordered.sort()
	return {"count":ordered.size(),
		"p50":ordered[maxi(0, ceili(float(ordered.size()) * 0.50) - 1)],
		"p95":ordered[maxi(0, ceili(float(ordered.size()) * 0.95) - 1)],
		"max":ordered.back(),"latest":values.back()}

func set_drive(drive: int) -> void:
	var previous_drive := current_drive
	var facing := -1 if drive < 0 else 1 if drive > 0 else current_facing
	if drive == current_drive and facing == current_facing: return
	current_drive = drive
	current_facing = facing
	var key := KEY_RIGHT if drive > 0 else KEY_LEFT if drive < 0 else 0
	var previous_key := KEY_RIGHT if previous_drive > 0 else KEY_LEFT if previous_drive < 0 else 0
	if drive != 0:
		intent_started_usec = Time.get_ticks_usec()
		if first_input_sync_offset_ms == null and synchronized_start_unix > 0.0:
			first_input_sync_offset_ms = (Time.get_unix_time_from_system() - synchronized_start_unix) * 1000.0
		intent_initial_x = world.platform.character_root.position.x + world.platform.visual_layer.position.x
		intent_initial_animation = world.platform.sprite.animation
		intent_visual_recorded = false
		intent_motion_recorded = false
		intent_owner_sample_recorded = false
	if previous_key != 0 and previous_key != key:
		inject_key(previous_key, false)
	if key != 0:
		inject_key(key, true)
	else:
		intent_started_usec = -1

func inject_key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _on_control_sent(control: Dictionary) -> void:
	var sequence := int(control.control_seq)
	send_at[sequence] = Time.get_ticks_usec()
	if intent_started_usec >= 0: input_at[sequence] = intent_started_usec

func _on_control_accepted(sequence: int) -> void:
	var now := Time.get_ticks_usec()
	if send_at.has(sequence):
		actions["control_send_to_accept_ms"].append(float(now - int(send_at[sequence])) / 1000.0)
	accepted_at[sequence] = now
	pending_owner_accepts[sequence] = now

func _on_motion_received(event: Dictionary) -> void:
	var applied_sequence := -1
	for sample in event.get("data", {}).get("players", []):
		if sample.get("player_id", "") == client.player_id:
			applied_sequence = int(sample.get("last_applied_control_seq", -1))
			break
	if applied_sequence < 0: return
	var now := Time.get_ticks_usec()
	if intent_started_usec >= 0 and not intent_owner_sample_recorded:
		actions["input_to_first_owner_sample_ms"].append(
			float(now - intent_started_usec) / 1000.0)
		intent_owner_sample_recorded = true
	for sequence in pending_owner_accepts.keys():
		if int(sequence) == applied_sequence:
			actions["accepted_to_owner_sample_ms"].append(
				float(now - int(pending_owner_accepts[sequence])) / 1000.0)
			if input_at.has(sequence):
				actions["input_to_applied_control_sample_ms"].append(
					float(now - int(input_at[sequence])) / 1000.0)
			pending_owner_accepts.erase(sequence)
			input_at.erase(sequence)
		elif int(sequence) < applied_sequence:
			superseded_owner_sequences += 1
			pending_owner_accepts.erase(sequence)
			input_at.erase(sequence)

func short_turn_tap(direction: int) -> void:
	var code := KEY_RIGHT if direction > 0 else KEY_LEFT
	var start_usec := Time.get_ticks_usec()
	var start_position := int(client.world_replica.local_player().motion.position_mm)
	var animation_before: StringName = world.platform.sprite.animation
	inject_key(code, true)
	var visible_ms: Variant = null
	var deadline := start_usec + 80000
	while Time.get_ticks_usec() < deadline and visible_ms == null:
		await process_frame
		if world.platform.sprite.animation != animation_before:
			visible_ms = float(Time.get_ticks_usec() - start_usec) / 1000.0
	inject_key(code, false)
	var released_usec := Time.get_ticks_usec()
	await create_timer(0.2).timeout
	short_tap_result = {"visible_reaction_ms":visible_ms,
		"held_ms":float(released_usec - start_usec) / 1000.0,
		"start_position_mm":start_position,
		"end_position_mm":int(client.world_replica.local_player().motion.position_mm),
		"velocity_mm_s":int(client.world_replica.local_player().motion.velocity_mm_s),
		"no_displacement":int(client.world_replica.local_player().motion.position_mm) == start_position
			and int(client.world_replica.local_player().motion.velocity_mm_s) == 0}
	short_tap_results.append(short_tap_result.duplicate(true))
	current_facing = direction

func run() -> void:
	# Bound the headless client while allowing its render loop to sample at 120 Hz.
	# The shipped world physics remains 60 Hz; the remote buffer budget allows
	# one 60-Hz render frame after its 100-ms interpolation delay.
	Engine.max_fps = 120
	role = int(OS.get_environment("S812_ROLE"))
	duration_s = int(OS.get_environment("S812_DURATION_S"))
	proxy_port = int(OS.get_environment("S812_GAME_PROXY_PORT"))
	profile = OS.get_environment("S812_PROFILE")
	output_path = OS.get_environment("S812_OUTPUT")
	sync_file = OS.get_environment("S812_SYNC_FILE")
	pre = root.get_node("Preworld")
	client = root.get_node("MmoClient")
	change_scene_to_file("res://scenes/mmo/login.tscn")
	if not await wait_until(func(): return current_scene != null, "Login scene loads"): finish(); return
	stage("login")
	client.control_sent.connect(_on_control_sent)
	client.control_accepted.connect(_on_control_accepted)
	client.world_replica.motion_received.connect(_on_motion_received)
	var ca := X509Certificate.new()
	check(ca.load(OS.get_environment("S812_CA")) == OK, "trusted Beta CA loads")
	await pre.login("localhost", int(OS.get_environment("S812_LOGIN_PORT")),
		OS.get_environment("S812_USERNAME"), OS.get_environment("S812_PASSWORD"), "internet_beta", ca)
	stage("login_return_" + pre.state)
	if not await wait_until(func(): return pre.state == "REALMS", "password Login succeeds"): finish(); return
	await pre.select_realm(0)
	stage("realm_return_" + pre.state)
	if not await wait_until(func(): return pre.state == "LOBBY", "selected realm Lobby succeeds"): finish(); return
	if pre.roster.get("characters", []).is_empty():
		var model_id := "kotone" if role == 1 else "yuna"
		pre.show_creator()
		var payload: Dictionary = pre.catalog.character_models[model_id].default_payload.duplicate(true)
		await pre.create_character("S812 profile " + str(role), payload)
		if not await wait_until(func(): return pre.state == "LOBBY" and pre.roster.characters.size() == 1,
			"durable profile character created"): finish(); return
	var selected_id: String = pre.roster.characters[0].character_id
	await pre.select_character(selected_id)
	if not await wait_until(func(): return pre.state == "LOBBY" and not pre.selection.is_empty(),
		"owned character selected"): finish(); return
	var selected: Dictionary = pre.selection.character.duplicate(true)
	stage("selected")
	var handoff_reply: Dictionary = await pre._operation("world_enter", {})
	stage("handoff_return_" + str(handoff_reply.get("status", "empty")))
	if handoff_reply.is_empty() or handoff_reply.get("status") != "ok":
		check(false, "one-time world handoff obtained"); finish(); return
	var handoff: Dictionary = handoff_reply.data.duplicate(true)
	if proxy_port > 0:
		handoff.game.host = "127.0.0.1"
		handoff.game.port = proxy_port
	pre._state("WORLD")
	check(client.enter_character(handoff, selected, "internet_beta", ca), "native Game TLS connection starts")
	if not await wait_until(func(): return client.state == "READY", "native Game TLS snapshot is ready"): finish(); return
	stage("game_ready")
	change_scene_to_file("res://scenes/mmo/world.tscn")
	if not await wait_until(func(): return current_scene != null and current_scene.get("platform") != null,
		"world presentation loads"): finish(); return
	world = current_scene
	if not await wait_until(func(): return client.world_replica.view().players.size() == 2,
		"second authenticated Godot client becomes visible", 45.0): finish(); return
	stage("two_players")
	var remote_id := ""
	for id in client.world_replica.view().players:
		if id != client.player_id: remote_id = id
	var own_x := int(client.world_replica.local_player().motion.position_mm)
	var remote_x := int(client.world_replica.view().players[remote_id].motion.position_mm)
	approach_direction = 1 if own_x < remote_x else -1
	stage("remote_renderer_wait")
	if not await wait_until(func(): return world.platform.remote_players.has(remote_id), "remote renderer is live"): finish(); return
	stage("remote_renderer_ready")
	var remote: Node = world.platform.remote_players[remote_id]
	var initial_facing := int(client.world_replica.local_player().motion.get("facing", 1))
	await short_turn_tap(-initial_facing)
	if current_facing == approach_direction:
		await short_turn_tap(-approach_direction)
	check(bool(short_tap_result.get("no_displacement", false)),
		"short turn tap changes facing without authoritative movement")
	var ready_file := FileAccess.open(sync_file + ".ready" + str(role), FileAccess.WRITE)
	ready_file.store_string("ready")
	ready_file.close()
	if not await wait_until(func(): return FileAccess.file_exists(sync_file + ".ready1") and FileAccess.file_exists(sync_file + ".ready2"), "both Game clients ready for synchronized controls", 30.0): finish(); return
	if not await wait_until(func(): return FileAccess.file_exists(sync_file + ".go"), "synchronized control start", 30.0): finish(); return
	# Pre-barrier taps verify the local short-action contract but do not belong
	# to synchronized owner/observer performance distributions.
	for values in actions.values(): values.clear()
	send_at.clear(); accepted_at.clear(); input_at.clear(); pending_owner_accepts.clear()
	var go_at := float(FileAccess.get_file_as_string(sync_file + ".go"))
	synchronized_start_unix = go_at
	while Time.get_unix_time_from_system() < go_at: await process_frame
	stage("synchronized_start")
	initial_remote_sample_usec = remote.last_motion_sample_received_usec
	initial_remote_visual_x = remote.visual_x
	var start_usec := Time.get_ticks_usec()
	var next_snapshot_usec := start_usec
	var next_state_usec := start_usec + 30000000
	var last_remote_sample_usec: int = remote.last_motion_sample_received_usec
	var tracking_remote_onset := false
	var remote_start_x: float = remote.visual_x
	var next_client_drive_usec := start_usec
	while Time.get_ticks_usec() - start_usec < duration_s * 1000000:
		if not is_instance_valid(world) or pre.state != "WORLD" or client.state in ["FAILED", "DISCONNECTED"]:
			failures.append("Game client/session left the synchronized profile before completion")
			stage("client_left_world")
			finish()
			return
		var elapsed_s := float(Time.get_ticks_usec() - start_usec) / 1000000.0
		var cycle_period := 8.0 if profile == "long_session" else 4.0
		var cycle := fposmod(elapsed_s, cycle_period)
		var drive := 0
		if cycle < cycle_period * 0.375: drive = approach_direction
		elif cycle >= cycle_period * 0.625 and cycle < cycle_period * 0.875: drive = -approach_direction
		if Time.get_ticks_usec() >= next_client_drive_usec and drive != current_drive:
			stage("set_drive_" + str(drive))
			await set_drive(drive)
			stage("drive_done_" + str(drive))
			next_client_drive_usec = Time.get_ticks_usec() + 50000
		if intent_started_usec >= 0:
			var visible_x: float = world.platform.character_root.position.x + world.platform.visual_layer.position.x
			var animation_changed: bool = world.platform.sprite.animation != intent_initial_animation
			if not intent_visual_recorded and (animation_changed or absf(visible_x - intent_initial_x) > 0.001):
				actions["intent_to_local_visual_ms"].append(
					float(Time.get_ticks_usec() - intent_started_usec) / 1000.0)
				intent_visual_recorded = true
			if not intent_motion_recorded and absf(visible_x - intent_initial_x) > 0.001:
				actions["intent_to_local_motion_ms"].append(
					float(Time.get_ticks_usec() - intent_started_usec) / 1000.0)
				intent_motion_recorded = true
		var local_motion: Dictionary = client.world_replica.local_player().get("motion", {})
		var received_usec: int = remote.last_motion_sample_received_usec
		if received_usec > last_remote_sample_usec:
			last_remote_sample_usec = received_usec
			var remote_velocity := int(client.world_replica.view().players.get(remote_id, {}).get("motion", {}).get("velocity_mm_s", 0))
			if remote_velocity != 0 and (last_remote_velocity == 0
				or signi(last_remote_velocity) != signi(remote_velocity)):
				tracking_remote_onset = true
				first_motion_sample_usec = received_usec
				remote_start_x = remote.visual_x
			last_remote_velocity = remote_velocity
			if remote_velocity == 0: last_remote_velocity = 0
		if tracking_remote_onset:
			if absf(remote.visual_x - remote_start_x) > 0.001:
				var visible_usec := Time.get_ticks_usec()
				var latency := float(visible_usec - first_motion_sample_usec) / 1000.0
				remote_onset_times.append(latency)
				actions["sample_receipt_to_remote_visual_ms"].append(latency)
				if intent_started_usec >= 0:
					actions["input_to_remote_visual_ms"].append(
						float(visible_usec - intent_started_usec) / 1000.0)
				tracking_remote_onset = false
		if Time.get_ticks_usec() >= next_state_usec and current_drive == 0 and client._pending.is_empty():
			client.request_state()
			next_state_usec += 30000000
		if Time.get_ticks_usec() >= next_snapshot_usec:
			var timeline := {}
			for id in world.platform.remote_players:
				timeline[id] = world.platform.remote_players[id].timeline_metrics()
			snapshots.append({"elapsed_s": elapsed_s,
				"game_state": client.state,
				"local_input": client._server_input.duplicate(),
				"pending_request": str(client._pending.get("op", "")),
				"scheduled_request": str(client._scheduled.get("op", "")),
				"tcp_receive_buffer_bytes": client._channel._receive.size() if client._channel != null else 0,
				"tcp_send_buffer_bytes": client._channel._send.size() if client._channel != null else 0,
				"owner_history_size": world.platform._prediction_history.size(),
				"owner_metrics": world.platform.prediction_metrics(),
				"remote_metrics": timeline,
				"visible_players": client.world_replica.view().players.size(),
				"simulation_tick": int(local_motion.get("simulation_tick", 0)),
				"local_control_sequence": int(local_motion.get("last_applied_control_seq", 0))})
			next_snapshot_usec += 1000000
		await process_frame
	stage("loop_finished")
	await set_drive(0)
	if not await wait_until(func(): return client._server_input.drive == 0 and client.world_replica.local_player().motion.velocity_mm_s == 0,
		"authoritative motion stops before logout", 10.0): finish(); return
	final_owner_metrics = world.platform.prediction_metrics()
	for id in world.platform.remote_players:
		final_remote_metrics[str(id)] = world.platform.remote_players[id].timeline_metrics()
	stage("metrics_captured")
	check(client.logout(), "safe Logout request is sent")
	stage("logout_requested")
	if not await wait_until(func(): return pre.state == "LOBBY", "safe Logout and final save complete", 25.0): finish(); return
	stage("logout_completed")
	var summary := {"profile":profile,"role":role,"duration_s":duration_s,
		"frame_rate_limit_hz":Engine.max_fps,
		"godot_version":Engine.get_version_info().string,
		"transport":"native Godot TLS; endpoint may pass through encrypted-byte loopback proxy",
		"actions": {"intent_to_local_visual_ms":distribution(actions["intent_to_local_visual_ms"]),
			"intent_to_local_motion_ms":distribution(actions["intent_to_local_motion_ms"]),
			"control_send_to_accept_ms":distribution(actions["control_send_to_accept_ms"]),
			"input_to_first_owner_sample_ms":distribution(actions["input_to_first_owner_sample_ms"]),
			"input_to_applied_control_sample_ms":distribution(actions["input_to_applied_control_sample_ms"]),
			"accepted_to_owner_sample_ms":distribution(actions["accepted_to_owner_sample_ms"]),
			"sample_receipt_to_remote_visual_ms":distribution(actions["sample_receipt_to_remote_visual_ms"]),
			"input_to_remote_visual_ms":distribution(actions["input_to_remote_visual_ms"])},
		"superseded_owner_sequences_before_sample":superseded_owner_sequences,
		"owner_metrics":final_owner_metrics,
		"remote_metrics":final_remote_metrics,"snapshots":snapshots,
		"short_turn_tap":short_tap_result,
		"short_turn_taps":short_tap_results,
		"synchronized_input_offset_ms_from_shared_start":first_input_sync_offset_ms,
		"logout_state":pre.state,"login_state":client.state,"checks_failed":failures.size(),
		"failures":failures}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary))
		file.close()
	print("S812_GODOT_RESULT " + JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)

func finish() -> void:
	var game_state: String = client.state if is_instance_valid(client) else "missing"
	var game_error: Dictionary = client.last_error.duplicate(true) if is_instance_valid(client) else {}
	var pre_state: String = pre.state if is_instance_valid(pre) else "missing"
	var pre_error: Dictionary = pre.error.duplicate(true) if is_instance_valid(pre) else {}
	if client != null and client.state not in ["IDLE", "DISCONNECTED", "FAILED"]:
		client.disconnect_world()
	print("S812_GODOT_RESULT " + JSON.stringify({"profile":profile,"role":role,
		"preworld_state":pre_state,
		"preworld_error":pre_error,
		"game_state":game_state,
		"game_error":game_error,
		"game_state_after_disconnect":client.state if is_instance_valid(client) else "missing",
		"failures":failures,"result":"FAIL"}))
	quit(1)
