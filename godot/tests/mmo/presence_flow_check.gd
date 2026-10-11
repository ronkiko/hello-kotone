extends SceneTree
## Two native TLS Godot windows deliberately transfer one character's control.
var checks := 0
var failures: Array = []
var role := 1
var sync := ""
var pre: Node
var client: Node
var takeover_offers: Array[Dictionary] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func wait_for(predicate: Callable, label: String, seconds: float = 20.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < until:
		await process_frame
	check(predicate.call(), label)
	return predicate.call()
func mark(name: String, value: Dictionary = {}) -> void:
	var file := FileAccess.open(sync.path_join(name + ".pending"), FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(sync.path_join(name + ".pending"), sync.path_join(name))
func load_mark(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(sync.path_join(name)))
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	role = int(OS.get_environment("LOBBY09_ROLE"))
	sync = OS.get_environment("LOBBY09_SYNC")
	pre = root.get_node("Preworld")
	client = root.get_node("MmoClient")
	pre.takeover_offered.connect(func(character: Dictionary): takeover_offers.append(character))
	var ca := X509Certificate.new()
	check(ca.load(OS.get_environment("LOBBY09_CA")) == OK, "trusted certificate loaded")
	if role == 2 and not await wait_for(func(): return FileAccess.file_exists(sync.path_join("avatar")), "first window has live avatar"): finish(); return
	await pre.login("localhost", int(OS.get_environment("LOBBY09_LOGIN_PORT")), "member", OS.get_environment("LOBBY09_PASSWORD"), "internet_beta", ca)
	if not await wait_for(func(): return pre.state == "REALMS", "fresh password Login"): finish(); return
	await pre.select_realm(0)
	if not await wait_for(func(): return pre.state == "LOBBY", "fresh authenticated Lobby"): finish(); return
	if role == 1:
		pre.show_creator()
		await pre.create_character("Takeover Kotone", pre.catalog.character_models.kotone.default_payload)
		if not await wait_for(func(): return pre.state == "LOBBY" and pre.roster.characters.size() == 1, "durable character created"): finish(); return
		await pre.select_character(pre.roster.characters[0].character_id)
		await pre.enter_world()
	else:
		var original := load_mark("avatar")
		check(pre.roster.characters.size() == 1 and pre.roster.characters[0].character_id == original.player_id, "same owned character in fresh roster")
		var client_state_before_select: String = client.state
		var client_requests_before_select: int = client._request_count
		await pre.select_character(original.player_id)
		check(pre.state == "LOBBY" and takeover_offers.size() == 1
			and takeover_offers[0].character_id == original.player_id,
			"CHARACTER_ONLINE offers explicit takeover for the owned character")
		check(client.state == client_state_before_select and client.player_id.is_empty()
			and client.session_id.is_empty() and client._request_count == client_requests_before_select,
			"online rejection never starts takeover before explicit user action (state %s → %s, requests %d → %d)" % [
			client_state_before_select, client.state, client_requests_before_select, client._request_count])
		await pre.resume_character(original.player_id)
	if not await wait_for(func(): return client.state == "READY", "world snapshot and new control route"): finish(); return
	change_scene_to_file("res://scenes/mmo/world.tscn")
	await process_frame
	if current_scene != null and current_scene.get("input_adapter") != null:
		current_scene.input_adapter.set_physics_process(false)
	var local: Dictionary = client.world_replica.local_player()
	if role == 1:
		mark("avatar", {"player_id": client.player_id, "session_fingerprint": client.session_id.sha256_text(), "position_mm": local.motion.position_mm})
		if not await wait_for(func(): return pre.state == "LOGIN" and pre.error.get("code") == "SESSION_REPLACED", "healthy window receives explicit kick"): finish(); return
		check(client.session_id.is_empty() and client.player_id.is_empty() and client._pending.is_empty(), "revoked window clears command and prediction authority")
		var request_count: int = client._request_count
		mark("kicked")
		if not await wait_for(func(): return FileAccess.file_exists(sync.path_join("done")), "replacement completes gameplay and safe logout", 30.0): finish(); return
		check(client._request_count == request_count and pre.state == "LOGIN", "former window never takes control back automatically")
	else:
		var original := load_mark("avatar")
		check(client.player_id == original.player_id and client.session_id.sha256_text() != original.session_fingerprint, "same avatar and fresh session")
		check(client.world_replica.view().players.size() == 1, "one physical entity")
		check(client._server_input_seq == 0 and local.motion.last_applied_control_seq == 0, "new control namespace starts at zero")
		if not await wait_for(func(): return FileAccess.file_exists(sync.path_join("kicked")), "first window is fenced"): finish(); return
		var start: int = local.motion.position_mm
		check(client.set_control(1, 1), "replacement sends first control")
		if not await wait_for(func(): return client._server_input_seq == 1 and client.world_replica.local_player().motion.position_mm > start + 200, "replacement immediately controls live avatar"): finish(); return
		check(client.set_control(0, 1), "replacement releases control")
		if not await wait_for(func(): return client._server_input_seq == 2 and client.state == "READY" and client.world_replica.local_player().motion.velocity_mm_s == 0, "authoritative rest before logout"): finish(); return
		var logout_at := Time.get_ticks_msec()
		check(client.logout(), "safe logout requested")
		if not await wait_for(func(): return pre.state == "LOBBY", "final save returns roster", 20.0): finish(); return
		check(Time.get_ticks_msec() - logout_at >= 10000, "full server ten-second quiet period")
		check(client.session_id.is_empty() and pre.roster.characters[0].character_id == original.player_id, "final durability clears control and preserves character")
		mark("done")
	finish()
func finish() -> void:
	print("PRESENCE11_RESULT ", JSON.stringify({"role": role, "checks": checks, "failures": failures, "passed": failures.is_empty(), "display_backend": DisplayServer.get_name()}))
	quit(0 if failures.is_empty() else 1)
