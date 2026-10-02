extends Node
## Persistent session core. No renderer references, server imports, or automatic replay.

signal state_changed(state: String)
signal fault(info: Dictionary)
signal response_received(op: String, data: Dictionary)
signal event_received(event: Dictionary)
signal move_rejected(code: String)
signal move_intended(direction: String)
signal world_ready
signal disconnected

const Protocol = preload("res://scripts/mmo/protocol_v4.gd")
const Channel = preload("res://scripts/mmo/tcp_channel.gd")
const MapCache = preload("res://scripts/mmo/map_cache.gd")
const Replica = preload("res://scripts/mmo/world_replica.gd")
const REQUEST_LIMIT := 4096
const REQUEST_INTERVAL_MS := 75 # Server public minimum is 50 ms.
var state := "IDLE"
var last_error: Dictionary = {}
var player_id := ""
var session_id := ""
var initial_snapshot: Dictionary = {}
var last_snapshot: Dictionary = {}
var map_document: Dictionary = {}
var world_replica := Replica.new()
var map_cache := MapCache.new()
var map_source := ""
var connect_timeout_ms := 5000
var request_timeout_ms := 20000
var write_timeout_ms := 5000
var frame_timeout_ms := 10000
var _connection_generation := 0
var _login_endpoint: Dictionary = {}
var login_endpoint: Dictionary:
	get: return _login_endpoint.duplicate(true)
var _channel: RefCounted
var _ticket := ""
var _nickname := ""
var _pending: Dictionary = {}
var _scheduled: Dictionary = {}
var _request_deadline := 0
var _next_request_at := 0
var _request_count := 0
var _world_rules: Dictionary = {}
var world_rules: Dictionary:
	get: return _world_rules.duplicate(true)
var _next_move_at := 0
var _move_fact: Dictionary = {}

func connect_world(host: String, port: int, nickname: String) -> bool:
	if state not in ["IDLE", "DISCONNECTED", "FAILED"]:
		return false
	_clear_session()
	last_error = {}
	if not Protocol.matches(host, "^[A-Za-z0-9.:-]{1,253}$") or not Protocol.integer(port, 1, 65535) or not Protocol.token(nickname):
		_fail("INVALID_CONFIG")
		return false
	_login_endpoint = {"host": host, "port": port, "nickname": nickname}
	_nickname = nickname
	_open(host, port, "CONNECTING_LOGIN")
	return state != "FAILED"

func reconnect_world() -> bool:
	# Explicit human action only: new Login/ticket/enter, never a saved mutation.
	if _login_endpoint.is_empty():
		return false
	return connect_world(_login_endpoint.host, _login_endpoint.port, _login_endpoint.nickname)

func move(direction: String) -> bool:
	if direction not in ["left", "right"] or Time.get_ticks_msec() < _next_move_at:
		return false
	if not _public_request("move", {"direction": direction}):
		return false
	_move_fact = {}
	_next_move_at = Time.get_ticks_msec() + _world_rules.movement.min_move_interval_ms
	_set_state("MOVING")
	# A local observer may cancel synchronously. Unsent intentions are not facts.
	if state != "MOVING":
		return false
	move_intended.emit(direction)
	return state == "MOVING"

func request_state() -> bool:
	if not _public_request("state"):
		return false
	world_replica.begin_resync()
	_set_state("RESYNCING")
	return true

func request_map() -> bool:
	return _public_request("map")

func logout() -> bool:
	if not _public_request("logout"):
		return false
	_set_state("LOGGING_OUT")
	return true

func disconnect_world() -> void:
	# Explicit cancellation closes the socket; it never claims a successful flush.
	if not _pending.is_empty() and _pending.op in ["login", "enter", "move", "logout"]:
		_fail("CANCELLED")
	else:
		_close_cleanly()

func _public_request(op: String, payload: Dictionary = {}) -> bool:
	if state != "READY" or not _pending.is_empty() or not _scheduled.is_empty():
		return false
	_schedule(op, payload)
	return true

func _open(host: String, port: int, next_state: String) -> void:
	if _channel != null:
		_channel.close()
	_connection_generation += 1
	_request_count = 0
	_next_request_at = 0
	_channel = Channel.new()
	_channel.connect_timeout_ms = connect_timeout_ms
	_channel.write_timeout_ms = write_timeout_ms
	_channel.frame_timeout_ms = frame_timeout_ms
	_channel.connected.connect(_channel_connected.bind(_connection_generation))
	_channel.frame_received.connect(_channel_frame.bind(_connection_generation))
	_channel.failed.connect(_channel_failed.bind(_connection_generation))
	var generation := _connection_generation
	_set_state(next_state)
	if generation == _connection_generation:
		_channel.open(host, port)

func _channel_connected(generation: int) -> void:
	if generation == _connection_generation:
		_on_connected()

func _channel_frame(frame: PackedByteArray, generation: int) -> void:
	if generation == _connection_generation:
		_on_frame(frame)

func _channel_failed(code: String, generation: int) -> void:
	if generation == _connection_generation:
		_fail(code)

func _on_connected() -> void:
	if state == "CONNECTING_LOGIN":
		_set_state("AUTHORIZING")
		if state == "AUTHORIZING":
			_schedule("login", {"nickname": _nickname})
	elif state == "CONNECTING_GAME":
		_set_state("ENTERING_WORLD")
		if state == "ENTERING_WORLD":
			_schedule("enter", {"ticket": _ticket})
			_ticket = ""

func _schedule(op: String, payload: Dictionary) -> void:
	_scheduled = {"op": op, "payload": payload}

func _process(_delta: float) -> void:
	if _channel == null or state in ["IDLE", "DISCONNECTED", "FAILED"]:
		return
	var generation := _connection_generation
	_channel.poll()
	if generation != _connection_generation:
		return
	if state in ["DISCONNECTED", "FAILED"]:
		return
	var now := Time.get_ticks_msec()
	if not _pending.is_empty() and now >= _request_deadline:
		_fail("REQUEST_TIMEOUT")
		return
	if _scheduled.is_empty() or not _pending.is_empty() or now < _next_request_at:
		return
	if _request_count >= REQUEST_LIMIT:
		_fail("REQUEST_LIMIT")
		return
	_request_count += 1
	_pending = {"op": _scheduled.op, "request_id": "r%d" % _request_count}
	var message := {"protocol_version": Protocol.VERSION, "type": "request", "request_id": _pending.request_id,
		"op": _scheduled.op, "payload": _scheduled.payload}
	var frame := (JSON.stringify(message) + "\n").to_utf8_buffer()
	_scheduled = {}
	_request_deadline = now + request_timeout_ms
	_next_request_at = now + REQUEST_INTERVAL_MS
	if not _channel.send(frame):
		_fail("WRITE_FAILED")

func _on_frame(frame: PackedByteArray) -> void:
	var message := Protocol.decode(frame)
	if message.is_empty():
		_fail("INVALID_MESSAGE")
		return
	if message.get("type") == "version_error":
		_fail("UNSUPPORTED_VERSION", true) if Protocol.version_error(message) else _fail("INVALID_MESSAGE")
		return
	if message.get("type") == "event":
		if session_id.is_empty() or not Protocol.event(message):
			_fail("INVALID_EVENT")
			return
		if not _pending.is_empty() and _pending.op == "move" and message.event == "moved" and message.data.player.player_id == player_id and not _move_fact.is_empty():
			_fail("MOVE_EVENT_MISMATCH")
			return
		if not world_replica.apply_event(message):
			_fail("STREAM_DESYNC")
			return
		# A synchronous replica observer may explicitly cancel the session.
		if session_id.is_empty():
			return
		if not _pending.is_empty() and _pending.op == "move" and message.event == "moved" and message.data.player.player_id == player_id:
			_move_fact = {"epoch": message.epoch, "zone_id": message.zone_id, "revision": message.revision, "player_id": player_id}
		last_snapshot = world_replica.snapshot()
		# Events never consume a request slot and do not replay after state resync.
		event_received.emit(message.duplicate(true))
		return
	if not Protocol.response(message):
		_fail("INVALID_MESSAGE")
		return
	if message.status == "error" and message.request_id == null:
		_fail(message.error.code)
		return
	if _pending.is_empty() or message.request_id != _pending.request_id or message.op != _pending.op:
		_fail("CORRELATION_ERROR")
		return
	if message.status != "ok":
		if _pending.op == "move" and message.status == "rejected" and message.error.code in ["OUT_OF_BOUNDS", "RATE_LIMITED", "WORLD_PAUSED"]:
			if not _move_fact.is_empty():
				_fail("MOVE_REJECTION_AFTER_EVENT")
				return
			var code: String = message.error.code
			_pending = {}
			_next_request_at = Time.get_ticks_msec() + REQUEST_INTERVAL_MS
			_next_move_at = Time.get_ticks_msec() + _world_rules.movement.min_move_interval_ms
			_set_state("READY")
			if state == "READY":
				move_rejected.emit(code)
			return
		_fail(message.error.code, true)
		return
	var op: String = _pending.op
	if op == "move" and (state != "MOVING" or _move_fact.is_empty() or message.data != _move_fact):
		_fail("MOVE_RECEIPT_MISMATCH")
		return
	_pending = {}
	# Spacing after receipt also covers a delayed/partial socket write.
	_next_request_at = Time.get_ticks_msec() + REQUEST_INTERVAL_MS
	var data: Dictionary = message.data
	match op:
		"login":
			# Credentials stay private and never appear in a signal or diagnostic.
			_ticket = data.ticket
			_open(data.game_server.host, data.game_server.port, "CONNECTING_GAME")
		"enter":
			player_id = data.player_id
			session_id = data.session_id
			initial_snapshot = data.snapshot.duplicate(true)
			last_snapshot = data.snapshot.duplicate(true)
			if not world_replica.start(data.snapshot, player_id, _nickname):
				_fail("SNAPSHOT_MISMATCH")
				return
			if session_id.is_empty():
				return
			_set_state("LOADING_MAP")
			var cached := map_cache.load_verified(world_replica.view().map)
			if cached.is_empty():
				_schedule("map", {})
			else:
				_accept_map(cached, "cache")
			if not session_id.is_empty():
				response_received.emit(op, data.duplicate(true))
		"map":
			if not _accept_map(data.map, "server"):
				return
			response_received.emit(op, data.duplicate(true))
		"world_rules":
			_world_rules = data.duplicate(true)
			_set_state("LOADING_STATE")
			_schedule("state", {})
			response_received.emit(op, data.duplicate(true))
		"state":
			if not _snapshot_matches(data.snapshot):
				_fail("SNAPSHOT_MISMATCH")
				return
			if session_id.is_empty():
				return
			last_snapshot = data.snapshot.duplicate(true)
			var loading := state == "LOADING_STATE"
			if loading or state == "RESYNCING":
				_set_state("READY")
			response_received.emit(op, data.duplicate(true))
			if loading and state == "READY":
				world_ready.emit()
		"move":
			_next_move_at = Time.get_ticks_msec() + _world_rules.movement.min_move_interval_ms
			_move_fact = {}
			_set_state("READY")
			if state == "READY":
				response_received.emit(op, data.duplicate(true))
		"logout":
			_close_cleanly()
			response_received.emit(op, data.duplicate(true))

func _accept_map(value: Dictionary, source: String) -> bool:
	if not _map_matches(value):
		_fail("MAP_MISMATCH")
		return false
	if not world_replica.install_map(value):
		_fail("SNAPSHOT_MISMATCH")
		return false
	if session_id.is_empty():
		return false
	map_document = value.duplicate(true)
	map_source = source
	if source == "server":
		# Disk failure affects only reuse; the validated live map remains usable.
		map_cache.store_verified(value, world_replica.view().map)
	if state == "LOADING_MAP":
		_set_state("LOADING_RULES")
		_schedule("world_rules", {})
	return true

func _map_matches(value: Dictionary) -> bool:
	var reference: Dictionary = world_replica.view().map
	return value.map_id == reference.map_id and value.content_version == reference.content_version \
		and value.content_hash == reference.content_hash

func _snapshot_matches(value: Dictionary) -> bool:
	return world_replica.replace_snapshot(value)

func _set_state(value: String) -> void:
	state = value
	state_changed.emit(state)

func _clear_session(preserve_replica: bool = false) -> void:
	_connection_generation += 1
	if _channel != null:
		_channel.close()
	_ticket = ""
	_pending = {}
	_scheduled = {}
	player_id = ""
	session_id = ""
	initial_snapshot = {}
	last_snapshot = {}
	map_document = {}
	map_source = ""
	_world_rules = {}
	_move_fact = {}
	_next_move_at = 0
	if not preserve_replica:
		world_replica.clear()

func _fail(code: String, known_outcome: bool = false) -> void:
	var op: String = _pending.get("op", "")
	last_error = {"code": code, "operation": op, "outcome_unknown": not known_outcome and op in ["login", "enter", "move", "logout"]}
	world_replica.invalidate(code)
	_clear_session(true)
	_set_state("FAILED")
	fault.emit(last_error.duplicate())

func _close_cleanly() -> void:
	_clear_session()
	_set_state("DISCONNECTED")
	disconnected.emit()

func _exit_tree() -> void:
	_clear_session()
