extends SceneTree
## Real Godot wire consumer; no Python proxy or server files.

var _client: Node
var _expected := ""
var _unknown := false
var _phase := 0
var _frames := 0
var _deadline := 0
var _finished := false
var _states: Array[String] = []
var _operations: Array[String] = []
var _evidence: Dictionary = {}
var _expect_events := false
var _expect_duplicate := false
var _fault_after_ready := false
var _events := 0
var _probe: Node

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	_client = root.get_node("MmoClient")
	var args := OS.get_cmdline_user_args()
	var options: Dictionary = {}
	for argument in args:
		var parts := argument.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	_expected = options.get("expect", "")
	_unknown = options.get("unknown", "false") == "true"
	_expect_events = options.get("events", "false") == "true"
	_expect_duplicate = options.get("duplicate", "false") == "true"
	_fault_after_ready = options.get("fault-after-ready", "false") == "true"
	if options.has("timeout-ms"):
		_client.request_timeout_ms = int(options["timeout-ms"])
	if options.has("frame-timeout-ms"):
		_client.frame_timeout_ms = int(options["frame-timeout-ms"])
	_client.state_changed.connect(func(value: String): _states.append(value))
	_client.fault.connect(_fault)
	_client.response_received.connect(_response)
	_client.event_received.connect(func(_event: Dictionary): _events += 1)
	_client.world_ready.connect(_ready_world)
	_deadline = Time.get_ticks_msec() + 15000
	_client.connect_world(options.get("host", "127.0.0.1"), int(options.get("port", "21060")), options.get("nickname", "player1"))

func _process(_delta: float) -> bool:
	_frames += 1
	if not _finished and _deadline != 0 and Time.get_ticks_msec() >= _deadline:
		finish(false, "OVERALL_TIMEOUT")
	return false

func _ready_world() -> void:
	if not _expected.is_empty() and not _fault_after_ready:
		finish(false, "UNEXPECTED_READY")
		return
	_evidence = {"player_id": _client.player_id, "map_id": _client.map_document.map_id,
		"bounds": [_client.map_document.min_x, _client.map_document.max_x],
		"snapshot_revision": _client.last_snapshot.revision, "realm": _client.world_session.view()}
	_phase = 1
	if _expect_events or _expect_duplicate:
		_probe = load("res://scripts/mmo/mmo_client.gd").new()
		root.add_child(_probe)
		_probe.fault.connect(func(info: Dictionary):
			if _expect_duplicate and info.code == "ALREADY_ONLINE" and not info.outcome_unknown and _client.state == "READY":
				begin_extra_state()
			else:
				finish(false, "SECOND_CLIENT_FAILED"))
		_probe.world_ready.connect(func(): _probe.logout())
		_probe.response_received.connect(func(op: String, _data: Dictionary):
			if op == "logout":
				begin_extra_state())
		# The runner uses a shared zone and a second nickname.
		var args := OS.get_cmdline_user_args()
		var port := 21060
		for argument in args:
			if argument.begins_with("port="):
				port = argument.trim_prefix("port=").to_int()
		_probe.connect_world("127.0.0.1", port, "player1" if _expect_duplicate else "player2")
	else:
		begin_extra_state()

func begin_extra_state() -> void:
	if not _client.request_state() or _client.request_map():
		finish(false, "PENDING_SLOT")

func _response(op: String, data: Dictionary) -> void:
	_operations.append(op)
	if op == "state" and _phase == 1:
		_phase = 2
		_client.logout()
	elif op == "logout":
		_evidence.flush = data.flush.status
		finish(_client.state == "DISCONNECTED" and _client.session_id.is_empty() and (not _expect_events or _events == 2), "CLEAN_LOGOUT")

func _fault(info: Dictionary) -> void:
	finish(info.code == _expected and info.outcome_unknown == _unknown and _client.session_id.is_empty(), str(info.code))

func finish(success: bool, reason: String) -> void:
	if _finished:
		return
	_finished = true
	_client.disconnect_world()
	if _probe != null:
		_probe.disconnect_world()
	print(JSON.stringify({"suite": "wire", "result": "PASS" if success else "FAIL", "reason": reason,
		"states": _states, "operations": _operations, "events": _events, "frames": _frames, "evidence": _evidence}))
	quit(0 if success else 1)
