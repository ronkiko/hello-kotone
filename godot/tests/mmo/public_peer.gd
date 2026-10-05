extends Node
## Acceptance-only second public peer using the same protocol-v5 held-input contract.

signal entered
signal replied(op: String)
signal failed
const Protocol = preload("res://scripts/mmo/protocol_v7.gd")
const Channel = preload("res://scripts/mmo/tcp_channel.gd")
var player_id := ""
var _channel: RefCounted
var _pending: Dictionary = {}
var _scheduled: Dictionary = {}
var _sequence := 0
var _next_at := 0
var _ticket := ""

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
	var data := {"protocol_version": Protocol.VERSION, "type": "request", "request_id": _pending.request_id,
		"op": _scheduled.op, "payload": _scheduled.payload}
	_scheduled = {}
	if not _channel.send((JSON.stringify(data) + "\n").to_utf8_buffer()):
		failed.emit()

func _frame(bytes: PackedByteArray) -> void:
	var value := Protocol.decode(bytes)
	if value.get("type") == "event":
		if not Protocol.event(value):
			failed.emit()
		return
	var valid: bool = Protocol.response(value)
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
