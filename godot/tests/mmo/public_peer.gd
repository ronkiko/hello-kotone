extends Node
## Acceptance-only second public peer; movement input API remains patch 05.

signal entered
signal replied(op: String)
signal failed
const Protocol = preload("res://scripts/mmo/protocol_v5.gd")
const Channel = preload("res://scripts/mmo/tcp_channel.gd")
var player_id := ""
var _channel: RefCounted
var _pending: Dictionary = {}
var _scheduled: Dictionary = {}
var _sequence := 0
var _next_at := 0
var _ticket := ""
var _last_moved: Dictionary = {}

func start(host: String, port: int) -> void:
	_open(host, port, "login", {"nickname": "player2"})

func request(op: String, payload: Dictionary = {}) -> void:
	_scheduled = {"op": op, "payload": payload}

func _open(host: String, port: int, op: String, payload: Dictionary) -> void:
	if _channel != null:
		_channel.close()
	_sequence = 0
	_next_at = 0
	_channel = Channel.new()
	_channel.connected.connect(func(): request(op, payload))
	_channel.frame_received.connect(_frame)
	_channel.failed.connect(func(_code: String): failed.emit())
	_channel.open(host, port)

func _process(_delta: float) -> void:
	if _channel == null:
		return
	_channel.poll()
	if not _pending.is_empty() or _scheduled.is_empty() or Time.get_ticks_msec() < _next_at:
		return
	_sequence += 1
	_pending = {"request_id": "p%d" % _sequence, "op": _scheduled.op}
	var data := {"protocol_version": 4, "type": "request", "request_id": _pending.request_id,
		"op": _scheduled.op, "payload": _scheduled.payload}
	_scheduled = {}
	if not _channel.send((JSON.stringify(data) + "\n").to_utf8_buffer()):
		failed.emit()

func _frame(bytes: PackedByteArray) -> void:
	var value := Protocol.decode(bytes)
	if value.get("type") == "event":
		if not Protocol.event(value):
			failed.emit()
		elif value.event == "moved" and value.data.player.player_id == player_id:
			_last_moved = value.duplicate(true)
		return
	var valid: bool = Protocol.response(value)
	if _pending.get("op") == "move":
		valid = Protocol.fields(value, ["protocol_version", "type", "request_id", "op", "status", "data", "error"]) \
			and value.protocol_version == 4 and value.type == "response" and value.status == "ok" and value.error == null \
			and Protocol.fields(value.data, ["epoch", "zone_id", "revision", "player_id"]) and not _last_moved.is_empty()
		if valid:
			valid = value.data.epoch == _last_moved.epoch and value.data.zone_id == _last_moved.zone_id \
				and value.data.revision == _last_moved.revision and value.data.player_id == player_id
	if not valid or _pending.is_empty() or value.request_id != _pending.request_id or value.op != _pending.op or value.status != "ok":
		failed.emit()
		return
	_pending = {}
	_next_at = Time.get_ticks_msec() + 80
	match value.op:
		"login":
			_ticket = value.data.ticket
			_open(value.data.game_server.host, value.data.game_server.port, "enter", {"ticket": _ticket})
			_ticket = ""
		"enter":
			player_id = value.data.player_id
			entered.emit()
		"logout":
			_channel.close()
	replied.emit(value.op)

func _exit_tree() -> void:
	if _channel != null:
		_channel.close()
