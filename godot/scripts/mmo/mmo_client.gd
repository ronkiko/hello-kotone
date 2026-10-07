extends Node
## Persistent session core. No renderer references, server imports, or automatic replay.

signal state_changed(state: String)
signal fault(info: Dictionary)
signal response_received(op: String, data: Dictionary)
signal event_received(event: Dictionary)
signal control_accepted(control_seq: int)
signal input_rejected(code: String)
signal world_ready
signal disconnected

const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const Protocol = preload("res://scripts/mmo/protocol_v8.gd")
const Channel = preload("res://scripts/mmo/tcp_channel.gd")
const MapCache = preload("res://scripts/mmo/map_cache.gd")
const Replica = preload("res://scripts/mmo/world_replica.gd")
const REQUEST_LIMIT := 4096

var state := "IDLE"
var last_error: Dictionary = {}
var player_id := ""
var session_id := ""
var initial_snapshot: Dictionary = {}
var last_snapshot: Dictionary = {}
var map_document: Dictionary = {}
var world_replica := Replica.new()
var world_session: RefCounted:
	get: return world_replica.world_session
var map_cache := MapCache.new()
var map_source := ""
var connect_timeout_ms := 5000
var request_timeout_ms := 20000
var write_timeout_ms := 5000
var frame_timeout_ms := 10000
var _connection_generation := 0
var _security_profile := "trusted_local_dev"
var _trusted_ca: X509Certificate
var _expected_identity := {}
var _expected_character := {}
var _leave_requested := false
var _channel: RefCounted
var _world_handoff := ""
var _nickname := ""
var _pending: Dictionary = {}
var _scheduled: Dictionary = {}
var _request_deadline := 0
var _next_request_at := 0
var _request_count := 0
var _session_rules: Dictionary = {}
var session_rules: Dictionary:
	get: return _session_rules.duplicate(true)
var _request_interval_ms := 0
var _last_request_at := 0
var _world_rules: Dictionary = {}
var world_rules: Dictionary:
	get: return _world_rules.duplicate(true)
var _desired_input := {"drive": 0, "facing": 1}
var _server_input := {"drive": 0, "facing": 1}
var _server_input_seq := 0

func prediction_control_state() -> Dictionary:
	# Predict the complete state that is current, queued, or will follow the
	# single in-flight request. Coalesced states never consume a wire sequence.
	var sequence := _server_input_seq
	if not _pending.is_empty() and _pending.op == "control_set":
		sequence = int(_pending.payload.control_seq)
		if _desired_input.drive != _pending.payload.drive or _desired_input.facing != _pending.payload.facing:
			sequence += 1
	elif not _scheduled.is_empty() and _scheduled.op == "control_set":
		sequence = int(_scheduled.payload.control_seq)
	elif _desired_input != _server_input:
		sequence += 1
	sequence = mini(sequence, 9007199254740991)
	var desired := _desired_input.duplicate()
	if state not in ["READY", "MOVING"] and not _leave_requested:
		desired.drive = 0
	return {"control_seq": sequence, "drive": desired.drive, "facing": desired.facing}

func enter_character(handoff: Dictionary, character: Dictionary, profile: String, ca: X509Certificate = null) -> bool:
	if state not in ["IDLE", "DISCONNECTED", "FAILED"]: return false
	_clear_session()
	last_error = {}
	if not Protocol.character_record(character) or not Protocol.identity(handoff.get("identity")) or not Protocol.endpoint(handoff.get("game")) or not Protocol.digest(handoff.get("world_handoff")) \
		or character.character_id != handoff.get("character_id") or character.game_card_id != handoff.identity.game_card_id or character.realm_id != handoff.identity.realm_id:
		_fail("CHARACTER_MISMATCH")
		return false
	_expected_identity = handoff.identity.duplicate(true)
	_expected_character = character.duplicate(true)
	_security_profile = profile
	_trusted_ca = ca
	_world_handoff = handoff.world_handoff
	_nickname = character.display_name
	_open(handoff.game.host, handoff.game.port, "CONNECTING_GAME")
	return state != "FAILED"

func set_control(drive: int, facing: int) -> bool:
	if _leave_requested or drive not in [-1, 0, 1] or facing not in [-1, 1] or state not in ["READY", "MOVING"] or _world_rules.is_empty(): return false
	_desired_input = {"drive": drive, "facing": facing}
	if _pending.is_empty() and _scheduled.get("op") == "control_set":
		_scheduled = {}
		_set_state("READY")
	_schedule_desired_input()
	return true

func _schedule_desired_input() -> void:
	if state == "READY" and _pending.is_empty() and _desired_input != _server_input and _scheduled.get("op") == "ping": _scheduled = {}
	if state != "READY" or _desired_input == _server_input or not _pending.is_empty() or not _scheduled.is_empty(): return
	if _server_input_seq >= 9007199254740991:
		_fail("CONTROL_NAMESPACE_EXHAUSTED")
		return
	_schedule("control_set", _desired_input.merged({"control_seq": _server_input_seq + 1}))
	_set_state("MOVING")

func request_state() -> bool:
	# A resync must not silently leave a held server input running while presentation freezes.
	if _desired_input.drive != 0 or _server_input.drive != 0:
		return false
	if not _public_request("state"):
		return false
	world_replica.begin_resync()
	_set_state("RESYNCING")
	return true

func request_map() -> bool:
	return _public_request("map")

func logout() -> bool:
	if state not in ["READY", "MOVING"]: return false
	_leave_requested = true
	_desired_input = {"drive": 0, "facing": _desired_input.facing}
	# Drain the single in-flight input, explicitly stop, then logout/flush.
	if _pending.is_empty() and _scheduled.get("op") in ["control_set", "ping"]:
		_scheduled = {}
		_set_state("READY")
	_advance_leave()
	return true

func _advance_leave() -> void:
	if not _leave_requested or state != "READY" or not _pending.is_empty() or not _scheduled.is_empty(): return
	if _server_input.drive != 0:
		_schedule("control_set", {"control_seq": _server_input_seq + 1, "drive": 0, "facing": _server_input.facing})
		_set_state("MOVING")
	else:
		_schedule("logout", {})
		_set_state("LOGGING_OUT")

func disconnect_world() -> void:
	# Explicit cancellation closes the socket; it never claims a successful flush.
	if not _pending.is_empty() and _pending.op in ["login", "enter", "control_set", "logout"]:
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
		_channel.open(host, port, _security_profile, _trusted_ca)

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
	if state == "CONNECTING_GAME":
		_set_state("LOADING_SESSION_RULES")
		if state == "LOADING_SESSION_RULES":
			_schedule("session_rules", {})

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
	# Human input wins the one public request slot. Keepalive only uses otherwise-idle time.
	if state == "READY" and _scheduled.is_empty() and _pending.is_empty():
		_advance_leave()
		_schedule_desired_input()
	if state == "READY" and _scheduled.is_empty() and _pending.is_empty() and not _session_rules.is_empty() and now - _last_request_at >= _session_rules.keepalive_interval_ms:
		_schedule("ping", {})
	if _scheduled.is_empty() or not _pending.is_empty() or now < _next_request_at:
		return
	if _request_count >= REQUEST_LIMIT:
		_fail("REQUEST_LIMIT")
		return
	_request_count += 1
	_pending = {"op": _scheduled.op, "request_id": "r%d" % _request_count,
		"payload": _scheduled.payload.duplicate(true)}
	var message := {"protocol_version": Protocol.VERSION, "type": "request", "request_id": _pending.request_id,
		"op": _scheduled.op, "payload": _scheduled.payload}
	var frame := (JSON.stringify(message) + "\n").to_utf8_buffer()
	_scheduled = {}
	_request_deadline = now + request_timeout_ms
	_next_request_at = now + _request_interval_ms
	if not _channel.send(frame):
		_fail("WRITE_FAILED")
	else:
		_last_request_at = now

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
		if message.event == "joined" and not _production_player(message.data.player):
			_fail("CHARACTER_MISMATCH")
			return
		if not world_replica.apply_event(message):
			_fail("STREAM_DESYNC")
			return
		# A synchronous replica observer may explicitly cancel the session.
		if session_id.is_empty():
			return
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
		if _pending.op == "control_set" and message.status == "rejected" and message.error.code in ["RATE_LIMITED", "WORLD_PAUSED"]:
			var input_code: String = message.error.code
			_pending = {}
			_desired_input = {"drive": 0, "facing": _desired_input.facing}
			_next_request_at = Time.get_ticks_msec() + _request_interval_ms
			var rejection_generation := _connection_generation
			_set_state("READY")
			if rejection_generation != _connection_generation:
				return
			input_rejected.emit(input_code)
			if rejection_generation != _connection_generation:
				return
			_schedule_desired_input()
			return
		_fail(message.error.code, true)
		return
	var completed: Dictionary = _pending.duplicate(true)
	var op: String = completed.op
	if op in ["map", "world_rules"] and not world_session.accepts_identity(message.data.identity):
		_fail("REALM_IDENTITY_MISMATCH")
		return
	if op == "enter":
		# Bind realm authority before reducer signals expose any zone projection.
		if message.data.player_id != _expected_character.get("character_id") or message.data.bootstrap.identity != _expected_identity or not _production_snapshot(message.data.snapshot) or not world_session.bind(message.data.bootstrap):
			_fail("REALM_BOOTSTRAP_MISMATCH")
			return
		for capability in ["map", "state", "world_rules", "control_set", "logout"]:
			if not world_session.supports(capability):
				_fail("WORLD_CAPABILITY_MISSING")
				return
	if op == "control_set" and not _valid_input_ack(message.data, completed):
		# Keep pending mutation context until validation: a malformed ACK is unknown.
		_fail("INPUT_BASELINE_MISMATCH")
		return
	_pending = {}
	# Spacing after receipt also covers a delayed/partial socket write.
	_next_request_at = Time.get_ticks_msec() + _request_interval_ms
	var data: Dictionary = message.data
	match op:
		"session_rules":
			_session_rules = data.duplicate(true)
			# Post-receipt spacing adds a clock-tick margin to advertised admission.
			_request_interval_ms = maxi(50, data.min_request_interval_ms + 1)
			_next_request_at = Time.get_ticks_msec() + _request_interval_ms
			_set_state("ENTERING_WORLD")
			if state == "ENTERING_WORLD":
				_schedule("enter", {"world_handoff": _world_handoff})
				_world_handoff = ""
		"ping":
			# Transport liveness only: no replica/scene/state_changed/world_ready.
			response_received.emit(op, data.duplicate(true))
		"enter":
			player_id = data.player_id
			session_id = data.session_id
			for item in data.snapshot.players:
				if item.player_id == player_id:
					_desired_input = {"drive": 0, "facing": item.motion.facing}
					_server_input = _desired_input.duplicate()
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
				response_received.emit(op, {"player_id": player_id, "snapshot": data.snapshot.duplicate(true)})
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
			if not _production_snapshot(data.snapshot) or not _snapshot_matches(data.snapshot):
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
		"control_set":
			_server_input_seq = data.control_seq
			_server_input = {"drive": completed.payload.drive, "facing": completed.payload.facing}
			var generation := _connection_generation
			_set_state("READY")
			if generation != _connection_generation: return
			control_accepted.emit(_server_input_seq)
			if generation != _connection_generation: return
			response_received.emit(op, data.duplicate(true))
			_schedule_desired_input()
		"logout":
			_close_cleanly()
			response_received.emit(op, data.duplicate(true))

func _valid_input_ack(data: Dictionary, completed: Dictionary) -> bool:
	return data.epoch == world_replica.view().epoch and data.zone_id == world_replica.local_player().get("zone_id") \
		and data.player_id == player_id and data.control_seq == completed.payload.get("control_seq") \
		and data.control_seq == _server_input_seq + 1

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
	_world_handoff = ""
	_trusted_ca = null
	_expected_identity = {}
	_expected_character = {}
	_leave_requested = false
	_pending = {}
	_scheduled = {}
	player_id = ""
	session_id = ""
	initial_snapshot = {}
	last_snapshot = {}
	map_document = {}
	map_source = ""
	_session_rules = {}
	_request_interval_ms = 0
	_last_request_at = 0
	_world_rules = {}
	world_session.invalidate()
	_desired_input = {"drive": 0, "facing": _desired_input.facing}
	_server_input = {"drive": 0, "facing": 1}
	_server_input_seq = 0
	if not preserve_replica:
		world_replica.clear()

func _fail(code: String, known_outcome: bool = false) -> void:
	var op: String = _pending.get("op", "")
	last_error = {"code": code, "operation": op, "outcome_unknown": not known_outcome and op in ["login", "enter", "control_set", "logout"]}
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

func _production_player(player: Dictionary) -> bool:
	var character: Variant = player.get("character")
	return Protocol.presentation(character) and Appearance.supported(character.appearance_payload) and character.game_card_id == _expected_identity.get("game_card_id") and character.realm_id == _expected_identity.get("realm_id") \
		and character.character_id == player.player_id and character.display_name == player.nickname

func _production_snapshot(snapshot: Dictionary) -> bool:
	for player in snapshot.players:
		if not _production_player(player): return false
		if player.player_id == _expected_character.get("character_id") and player.character.appearance_payload != _expected_character.appearance_payload: return false
	return true
