extends SceneTree
## Two native TLS clients; Python injects only private server faults, never plays.
var client: Node
var pre: Node
var role := 1
var sync := ""
var checks := 0
var failures: Array[String] = []
var world: Node
var delay_until := 0
var delayed_frame := PackedByteArray()
var recovery_state_requests := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL ", label)
func mark(label: String) -> void:
	var file := FileAccess.open(sync.path_join(label + str(role)), FileAccess.WRITE)
	file.store_string("ready")
func wait_until(predicate: Callable, label: String, seconds: float = 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		if client.state == "FAILED": break
		await process_frame
	check(predicate.call(), label)
	if not predicate.call(): print("STATE ", pre.state, " ERROR ", JSON.stringify(pre.error), " GAME ", client.state, " GAME_ERROR ", JSON.stringify(client.last_error), " CONTROL ", JSON.stringify({"pending_op":client._pending.get("op"),"scheduled_op":client._scheduled.get("op"),"desired":client._desired_input,"server":client._server_input,"sequence":client._server_input_seq,"motion":client.world_replica.local_player().get("motion",{})}))
	return predicate.call()
func delayed_delivery(raw: PackedByteArray) -> void:
	var value = JSON.parse_string(raw.get_string_from_utf8())
	if value is Dictionary and value.get("event") == "motion_frame" and Time.get_ticks_msec() < delay_until:
		delayed_frame = raw
	else: client._on_frame(raw)
func committed_movement(initial_mm: int) -> bool:
	var motion: Dictionary = client.world_replica.local_player().get("motion", {})
	if abs(int(motion.get("position_mm", initial_mm)) - initial_mm) >= 100: return true
	# A startup delivery gap may legitimately demand a fresh press. Scripted
	# agents repeat that explicit press only after a valid healthy frame.
	if not client.visual_stalled and client._desired_input.drive == 0:
		client.set_control(-1 if role == 1 else 1, -1 if role == 1 else 1)
	return false
func run() -> void:
	client = root.get_node("MmoClient")
	pre = root.get_node("Preworld")
	role = int(OS.get_environment("LOBBY09_ROLE"))
	sync = OS.get_environment("LOBBY09_SYNC")
	change_scene_to_file("res://scenes/mmo/login.tscn")
	await process_frame
	await process_frame
	var ca := X509Certificate.new()
	check(ca.load(OS.get_environment("LOBBY09_CA")) == OK, "native CA")
	pre.login("127.0.0.1", int(OS.get_environment("LOBBY09_LOGIN_PORT")), OS.get_environment("LOBBY09_ACCOUNT"), OS.get_environment("LOBBY09_PASSWORD"), "internet_beta", ca)
	if not await wait_until(func(): return pre.state == "REALMS", "native TLS Login"): quit(1); return
	mark("login")
	pre.select_realm(0)
	if not await wait_until(func(): return pre.state == "LOBBY", "native Lobby"): quit(1); return
	pre.show_creator()
	var model := "kotone" if role == 1 else "yuna"
	pre.create_character("Handoff Kotone" if role == 1 else "Handoff Yuna", pre.catalog.character_models[model].default_payload)
	if not await wait_until(func(): return pre.state == "LOBBY" and pre.roster.characters.size() == 1, "durable native create"): quit(1); return
	pre.select_character(pre.roster.characters[0].character_id)
	if not await wait_until(func(): return not pre.selection.is_empty(), "native selected character"): quit(1); return
	pre.enter_world()
	if not await wait_until(func(): return client.state == "READY", "native Game admission"): quit(1); return
	if not await wait_until(func(): return current_scene != null and current_scene.get("platform") != null, "native World presentation"): quit(1); return
	world = current_scene
	client.response_received.connect(func(op: String, _data: Dictionary):
		if op == "state": recovery_state_requests += 1)
	if not await wait_until(func(): return client.world_replica.view().players.size() == 2 and client.frame_health.last_usec >= 0, "Kotone/Yuna ordinary frame stream"): quit(1); return
	var human_input: Node = world.input_adapter
	human_input.set_physics_process(false)
	# Scripted native agents must not release on desktop focus changes.
	# Keep signal fencing connected, but remove application notifications.
	world.remove_child(human_input)
	var original_session: String = client.session_id
	var connection: int = client._connection_generation
	if not await wait_until(func(): return client.set_control(-1 if role == 1 else 1, -1 if role == 1 else 1), "live motion during normal handoff"): quit(1); return
	var initial_mm: int = client.world_replica.local_player().motion.position_mm
	if not await wait_until(func(): return committed_movement(initial_mm), "actually committed movement before Worker activation"): quit(1); return
	mark("ready")
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join("handoff-done")), "normal repeated handoff completed", 40): quit(1); return
	check(client.session_id == original_session and client.frame_health.bars == 4, "healthy handoff preserves Game session")
	client.set_control(0, client._desired_input.facing)
	if not await wait_until(func(): return client.world_replica.local_player().get("motion", {}).get("velocity_mm_s", -1) == 0 and client.state == "READY", "stop at confirmed boundary before crash"): quit(1); return
	mark("handoff-observed")
	if not await wait_until(func(): return client.visual_stalled, "Worker failure detected from frame age"): quit(1); return
	var pose: Vector2 = world.platform.character_root.position
	var camera: Vector2 = world.platform.camera.position
	var remote_poses := {}
	for id in world.platform.remote_players: remote_poses[id] = world.platform.remote_players[id].position
	await create_timer(0.15).timeout
	check(world.platform.character_root.position == pose and world.platform.camera.position == camera, "owner/camera exact stalled coordinates")
	for id in remote_poses: check(world.platform.remote_players[id].position == remote_poses[id], "remote exact stalled coordinates")
	check(not client.set_control(1, 1), "no stalled controls")
	mark("stalled")
	if not await wait_until(func(): return not client.visual_stalled and client.world_replica.view().zone_generation > 1, "first ordinary frame automatically recovers"): quit(1); return
	check(client.session_id == original_session and client._connection_generation == connection and client.frame_health.bars == 4 and pre.state == "WORLD", "same TLS/session four green no Login")
	await physics_frame
	var sample: Dictionary = client.world_replica.local_player().motion
	var actual_mm: float = world.platform._pixel_to_server_mm(world.platform.character_root.position.x)
	check(absf(actual_mm - sample.position_mm) <= 1.0, "recovered coordinates within 1mm")
	check(client._desired_input.drive == 0 and human_input._require_release, "fresh physical press required")
	mark("recovered")
	# Delay ordinary sample delivery independently for one peer, while channel,
	# responses, keepalive, HUD and the server remain live. Coalesce on release.
	if role == 1:
		client._channel.frame_received.disconnect(client._channel_frame.bind(client._connection_generation))
		client._channel.frame_received.connect(delayed_delivery)
		delay_until = Time.get_ticks_msec() + int(client.frame_health.max_wait / 1000.0) + 200
		if not await wait_until(func(): return client.visual_stalled, "independent delivery gap stalls only one client"): quit(1); return
		mark("jitter-stalled")
		await create_timer(0.12).timeout
		delay_until = 0
		if not delayed_frame.is_empty(): client._on_frame(delayed_frame)
		check(not client.visual_stalled and client.frame_health.bars == 4, "coalesced ordinary frame restores four green immediately")
		client._channel.frame_received.disconnect(delayed_delivery)
		client._channel.frame_received.connect(client._channel_frame.bind(client._connection_generation))
	else:
		if not await wait_until(func(): return FileAccess.file_exists(sync.path_join("jitter-stalled1")), "peer independent jitter reached zero"): quit(1); return
		check(not client.visual_stalled and client.frame_health.bars == 4, "second client remains healthy during first delivery gap")
	mark("jitter-done")
	if not await wait_until(func(): return client.visual_stalled, "persistent Worker startup failure stalls"): quit(1); return
	mark("timeout-stalled")
	if not await wait_until(func(): return pre.state == "LOGIN", "T0+10s disconnect returns to Login", 13): quit(1); return
	check(client.session_id.is_empty() and pre.account_id.is_empty() and pre.selection.is_empty(), "all account Lobby Game leases cleared")
	check(recovery_state_requests == 0, "no additional recovery state snapshot")
	human_input.free()
	print("WORKER_RECOVERY_RESULT ", JSON.stringify({"role":role,"recovery_state_requests":recovery_state_requests,"checks":checks,"failures":failures,"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
