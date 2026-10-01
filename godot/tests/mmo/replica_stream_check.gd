extends SceneTree
## Actual MmoClient reduction, session lifecycle and second real public peer.

var _client: Node
var _remote: Node
var _options: Dictionary = {}
var _failures: Array[String] = []
var _events: Array[String] = []
var _ready_count := 0
var _states: Array[String] = []
var _phase := 0
var _finished := false
var _deadline := 0
var _evidence: Dictionary = {}

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		if parts.size() == 2:
			_options[parts[0]] = parts[1]
	_client = root.get_node("MmoClient")
	_client.world_ready.connect(_ready_world)
	_client.event_received.connect(_event)
	_client.response_received.connect(_response)
	_client.fault.connect(_fault)
	_client.world_replica.changed.connect(_replica_changed)
	_client.state_changed.connect(func(value: String): _states.append(value))
	_deadline = Time.get_ticks_msec() + 15000
	_client.connect_world("127.0.0.1", int(_options.get("port", "21060")), "player1")

func _process(_delta: float) -> bool:
	if not _finished and _deadline != 0 and Time.get_ticks_msec() >= _deadline:
		_check(false, "OVERALL_TIMEOUT")
		finish()
	return false

func _ready_world() -> void:
	_ready_count += 1
	var view: Dictionary = _client.world_replica.view()
	_check(view.status == "SYNCED" and view.confirmed_local_x == 50 and view.local_player_id == _client.player_id, "READY_BASELINE")
	_evidence = {"initial_revision": view.revision, "confirmed_local_x": view.confirmed_local_x}
	if _options.get("mode", "real") == "real":
		_phase = 1
		_check(_client.request_state(), "INITIAL_EXPLICIT_STATE")
		_remote = load("res://tests/mmo/public_peer.gd").new()
		root.add_child(_remote)
		_remote.failed.connect(func(): _check(false, "REMOTE_FAILED"); finish())
		_remote.entered.connect(_drive_remote)
		_remote.replied.connect(func(op: String):
			if op == "move":
				_remote.request("logout"))
		_remote.start("127.0.0.1", int(_options.port))
	elif _options.get("mode") == "resync_race":
		_phase = 2
		_check(_client.request_state(), "EXPLICIT_RESYNC")
	elif _options.get("mode") in ["rollback_state", "epoch_state", "map_state"]:
		_phase = 3
		_check(_client.request_state(), "INVALID_STATE_REQUEST")
	elif _options.get("mode") == "load_events":
		_check(view.revision == 3 and view.players.size() == 2 and view.players.p2.x == 52, "LOADING_EVENTS_BASELINE")
		_client.logout()
	elif _options.get("mode") == "disconnect_stale":
		pass
	elif _options.get("mode") == "old_epoch_after_reentry" and _ready_count == 1:
		_client.logout()
	elif _options.get("mode") == "old_epoch_after_reentry":
		_check(view.epoch == "e2" and view.revision == 1, "NEW_ENTER_RESETS_EPOCH_SEQUENCE")
	else:
		# Fault fixture sends its invalid event after the successful state baseline.
		pass

func _drive_remote() -> void:
	_remote.request("move", {"direction": "right"})

func _replica_changed() -> void:
	if _options.get("mode") == "cancel_callback" and _client.world_replica.view().revision == 2:
		_client.disconnect_world()
		_finish_cancel.call_deferred()

func _finish_cancel() -> void:
	_check(_client.state == "DISCONNECTED" and _client.last_snapshot.is_empty() and _client.world_replica.snapshot().is_empty(), "CALLBACK_CANCEL_STAYS_DISCONNECTED")
	_check(_events.is_empty(), "NO_EVENT_AFTER_CALLBACK_CANCEL")
	finish()

func _event(value: Dictionary) -> void:
	_events.append(value.event)
	var view: Dictionary = _client.world_replica.view()
	_check(view.revision == value.revision and view.epoch == value.epoch, "EVENT_APPLIED_BEFORE_SIGNAL")
	_check(view.confirmed_local_x == 50, "REMOTE_EVENT_PRESERVES_LOCAL")
	if _options.get("mode", "real") == "real":
		if value.event == "joined":
			_check(view.players.has(value.data.player.player_id), "REAL_JOINED")
		elif value.event == "moved":
			_check(view.players[value.data.player.player_id].x == 51, "REAL_MOVED")
		elif value.event == "left":
			_check(not view.players.has(value.data.player_id), "REAL_LEFT")
			_resync_after_left.call_deferred()
	elif _options.get("mode") == "resync_race" and value.revision == 4:
		_check(view.players.p2.x == 53 and view.status == "SYNCED", "POST_RESYNC_EVENT")
		_check(_ready_count == 1, "NO_SECOND_WORLD_READY")
		_evidence.final_revision = view.revision
		_client.logout()

func _resync_after_left() -> void:
	while not _finished and _client.state != "READY":
		await process_frame
	if _finished:
		return
	_phase = 4
	_check(_client.request_state(), "REAL_EXPLICIT_RESYNC")

func _response(op: String, _data: Dictionary) -> void:
	if op == "state" and _phase == 2:
		var view: Dictionary = _client.world_replica.view()
		_check(view.revision == 3 and view.players.p2.x == 52 and view.status == "SYNCED", "RESYNC_BOUNDARY")
	elif op == "state" and _phase == 4:
		_check(_events == ["joined", "moved", "left"], "REAL_ORDERED_STREAM")
		var view: Dictionary = _client.world_replica.view()
		_check(view.players.size() == 1 and view.revision == _evidence.initial_revision + 3 and view.status == "SYNCED", "REAL_RESYNC_NO_REPLAY")
		_check(_ready_count == 1, "NO_SECOND_WORLD_READY")
		_evidence.final_revision = view.revision
		_client.logout()
	elif op == "logout":
		_check(_client.world_replica.view().status == "EMPTY", "LOGOUT_CLEARS_REPLICA")
		if _options.get("mode") == "old_epoch_after_reentry" and _ready_count == 1:
			_client.connect_world("127.0.0.1", int(_options.port), "player1")
			return
		finish()

func _fault(info: Dictionary) -> void:
	var mode: String = _options.get("mode", "real")
	var view: Dictionary = _client.world_replica.view()
	var expected_code := "SNAPSHOT_MISMATCH" if mode in ["rollback_state", "epoch_state", "map_state", "outside_snapshot"] else ("DISCONNECTED" if mode == "disconnect_stale" else "STREAM_DESYNC")
	_check(info.code == expected_code, "EXPECTED_FAULT")
	_check(view.status == "STALE" and view.resync_required and view.reconnect_required and _client.session_id.is_empty(), "STALE_AND_FENCED")
	_check(view.confirmed_local_x == 50 and view.revision == 1, "LAST_CONFIRMED_DATA_RETAINED")
	_check(view.stale_reason == _options.get("reason", ""), "STALE_REASON")
	_check(not _client.request_state() and not _client.request_map(), "CORRUPT_STREAM_CANNOT_RESYNC")
	_evidence.stale_reason = view.stale_reason
	_evidence.confirmed_revision = view.revision
	finish()

func _check(value: bool, reason: String) -> void:
	if not value:
		_failures.append(reason)

func finish() -> void:
	if _finished:
		return
	_finished = true
	_client.disconnect_world()
	if _remote != null:
		_remote.queue_free()
	print(JSON.stringify({"suite": "replica", "result": "PASS" if _failures.is_empty() else "FAIL", "failures": _failures, "states": _states, "events": _events, "evidence": _evidence}))
	quit(0 if _failures.is_empty() else 1)
