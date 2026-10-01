extends SceneTree
## Exercise the shipped scenes and their real controls against public services.

var _client: Node
var _options: Dictionary = {}
var _states: Array[String] = []
var _failures: Array[String] = []
var _deadline := 0
var _finished := false
var _frames := 0
var _capture_dir := ""

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		if parts.size() == 2:
			_options[parts[0]] = parts[1]
	_capture_dir = _options.get("capture", "")
	_client = root.get_node("MmoClient")
	var instance_id: int = _client.get_instance_id()
	_deadline = Time.get_ticks_msec() + 15000
	_client.state_changed.connect(_audit_stage)
	if _options.has("timeout-ms"):
		_client.request_timeout_ms = int(_options["timeout-ms"])
	if _options.has("frame-timeout-ms"):
		_client.frame_timeout_ms = int(_options["frame-timeout-ms"])
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/mmo/login.tscn", "STARTUP_SCENE")
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _wait_scene("Login")
	var login: Control = current_scene
	_check(login.nickname.text == "player1" and login.host.text == "127.0.0.1" and login.port.value == 21060, "LOCAL_DEFAULTS")
	_check(_client.state == "IDLE" and not login.connect_button.disabled and login.cancel_button.disabled, "IDLE_CONTROLS")
	await _capture("startup")
	var scenario: String = _options.get("scenario", "")
	var expected: String = _options.get("expect", "")
	login.port.value = int(_options.get("port", "21060"))
	login.port.get_line_edit().text = _options.get("port", "21060")
	login.nickname.text = _options.get("nickname", "player1")
	if scenario == "invalid_config":
		login.host.text = "invalid address"
		expected = "INVALID_CONFIG"
	if scenario == "rejection_retry":
		login.nickname.text = "stranger"
	login.connect_button.pressed.emit()
	# Even a second activation in the same frame must not open another session.
	login.connect_button.pressed.emit()
	_check(login.connect_button.disabled and not login.nickname.editable or _client.state == "FAILED", "CONNECT_BUSY")
	if scenario == "cancel":
		login.cancel_button.pressed.emit()
		_check(_client.state == "DISCONNECTED" and not login.connect_button.disabled, "CANCELLED")
		await create_timer(0.25).timeout
		_check(current_scene == login and _client.state == "DISCONNECTED" and _client.session_id.is_empty(), "NO_LATE_TRANSITION")
		finish()
		return
	if scenario == "rejection_retry":
		await _wait_state("FAILED")
		if _finished:
			return
		_check(_client.last_error.code == "NICKNAME_NOT_ALLOWED", "RETRY_INITIAL_REJECTION")
		_check(login.status_label.text.contains("Nickname rejected"), "REJECTION_MESSAGE")
		await _capture("rejected")
		login.nickname.text = "player1"
		login.connect_button.pressed.emit()
	if not expected.is_empty() and _options.get("fault-after-ready", "false") != "true":
		await _wait_state("FAILED")
		if _finished:
			return
		_check(current_scene == login and _client.last_error.code == expected, "EXPECTED_FAULT")
		var unknown: bool = _options.get("unknown", "false") == "true"
		_check(_client.last_error.outcome_unknown == unknown, "STARTUP_UNKNOWN_OUTCOME")
		_check(login.status_label.text.contains("Server outcome unknown") == unknown, "STARTUP_UNKNOWN_MESSAGE")
		_check(not login.connect_button.disabled and login.nickname.editable and login.cancel_button.disabled, "RETRY_CONTROLS")
		_check(not login.status_label.text.is_empty(), "VISIBLE_ERROR")
		if expected == "CONNECT_FAILED":
			_check(login.status_label.text.contains("Cannot reach the server"), "OFFLINE_MESSAGE")
		if expected == "NICKNAME_NOT_ALLOWED":
			_check(login.status_label.text.contains("Nickname rejected"), "REJECTION_MESSAGE")
		_audit_text(login)
		await _capture("error")
		finish()
		return
	await _wait_scene("World")
	if _finished:
		return
	_check(_client.state == "READY" and not _client.map_document.is_empty() and not _client.last_snapshot.is_empty(), "READY_GATE")
	_check(_client.get_instance_id() == instance_id and not _client.session_id.is_empty(), "AUTOLOAD_SURVIVES")
	_check(_states.has("LOADING_MAP") and _states.has("LOADING_STATE") and _states.has("READY"), "ALL_LOADING_STAGES")
	var world: Control = current_scene
	_check(world.identity.text.contains("player1") and world.identity.text.contains(_client.map_document.map_id), "WORLD_IDENTITY")
	_check(world.position_label.text == "Position: 50", "CONFIRMED_POSITION")
	world.refresh_button.pressed.emit()
	_check(_client.state == "RESYNCING" and world.refresh_button.disabled and world.leave_button.disabled, "REFRESH_BUSY")
	await _wait_state("READY")
	if _finished:
		return
	_check(current_scene == world and _client.get_instance_id() == instance_id and _client.world_replica.view().status == "SYNCED", "REFRESH_PRESERVES_SCENE_AND_SESSION")
	_audit_text(world)
	await _capture("world")
	world.leave_button.pressed.emit()
	_check(_client.state == "LOGGING_OUT" and world.leave_button.disabled, "LOGOUT_BUSY")
	await _wait_scene("Login")
	if _finished:
		return
	_check(_client.get_instance_id() == instance_id and _client.session_id.is_empty(), "RETURN_AUTOLOAD")
	_check(not current_scene.connect_button.disabled, "RETURN_CONTROLS")
	if not expected.is_empty():
		_check(_client.state == "FAILED" and _client.last_error.code == expected, "LOGOUT_FAULT")
		var unknown: bool = _options.get("unknown", "false") == "true"
		_check(_client.last_error.outcome_unknown == unknown, "UNKNOWN_OUTCOME")
		_check(current_scene.status_label.text.contains("Server outcome unknown") == unknown, "UNKNOWN_MESSAGE")
	else:
		_check(_client.state == "DISCONNECTED", "CLEAN_LOGOUT")
	_audit_text(current_scene)
	await _capture("returned")
	finish()

func _process(_delta: float) -> bool:
	_frames += 1
	if not _finished and _deadline != 0 and Time.get_ticks_msec() >= _deadline:
		_check(false, "OVERALL_TIMEOUT")
		finish()
	return false

func _wait_state(value: String) -> void:
	while not _finished and _client.state != value:
		await process_frame

func _wait_scene(value: String) -> void:
	while not _finished and (current_scene == null or current_scene.name != value or not current_scene.is_node_ready()):
		await process_frame

func _audit_stage(value: String) -> void:
	_states.append(value)
	# The scene's own listener runs first. Deferred audits avoid listener ordering.
	if value not in ["FAILED", "DISCONNECTED", "READY"]:
		_audit_busy.call_deferred(value)

func _audit_busy(value: String) -> void:
	if current_scene != null and current_scene.name == "Login" and _client.state == value:
		_check(current_scene.connect_button.disabled and not current_scene.nickname.editable and not current_scene.host.editable and not current_scene.port.editable, "DISABLED_DURING_" + value)
		_check(not current_scene.status_label.text.is_empty(), "STATUS_" + value)

func _audit_text(node: Node) -> void:
	if node is Label or node is LineEdit or node is Button:
		var content: String = node.text
		_check(not content.to_lower().contains("ticket") and not content.contains("a".repeat(64)), "NO_TICKET_IN_UI")
		_check(_client.session_id.is_empty() or not content.contains(_client.session_id), "NO_SESSION_IN_UI")
	for child in node.get_children():
		_audit_text(child)

func _capture(name: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(_capture_dir.path_join(name + ".png"))
	_check(result == OK, "SCREENSHOT_" + name)

func _check(condition: bool, reason: String) -> void:
	if not condition:
		_failures.append(reason)

func finish() -> void:
	if _finished:
		return
	_finished = true
	_client.disconnect_world()
	print(JSON.stringify({"suite": "shell", "result": "PASS" if _failures.is_empty() else "FAIL", "reason": ",".join(_failures), "fault": _client.last_error, "states": _states, "frames": _frames}))
	quit(0 if _failures.is_empty() else 1)
