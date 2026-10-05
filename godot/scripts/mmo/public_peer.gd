extends Node
## One bounded request slot per connection. Secrets never leave this object's reply.
const Protocol = preload("res://scripts/mmo/protocol_v7.gd")
const Channel = preload("res://scripts/mmo/tcp_channel.gd")
signal connected_result(ok: bool)
signal reply_result(value: Dictionary)
signal lost(code: String)
var channel: RefCounted
var connected_ok := false
var last_failure := "CONNECT_FAILED"
var generation := 0
var pending := {}
var count := 0
var spacing_ms := 101
var next_at := 0
var deadline := 0
var last_at := 0

func open(endpoint: Dictionary, profile: String, ca: X509Certificate) -> bool:
	close()
	var visit := generation
	channel = Channel.new()
	channel.connected.connect(func():
		if visit == generation:
			connected_ok = true
			connected_result.emit(true))
	channel.frame_received.connect(_frame.bind(visit))
	channel.failed.connect(_failed.bind(visit))
	channel.open(endpoint.host, endpoint.port, profile, ca)
	if channel._closed: return false
	var result: bool = await connected_result
	return result and visit == generation

func close() -> void:
	generation += 1
	connected_ok = false
	if channel != null: channel.close()
	pending = {}
	deadline = 0
	count = 0
	spacing_ms = 101
	next_at = 0
	# Wake an abandoned coroutine; it must check its captured visit.
	connected_result.emit(false)
	reply_result.emit({})

func request(op: String, payload: Dictionary) -> Dictionary:
	if not connected_ok or not pending.is_empty(): return {}
	var visit := generation
	pending = {"op": op, "request_id": "r%d" % (count + 1)}
	while Time.get_ticks_msec() < next_at:
		await get_tree().process_frame
		if visit != generation: return {}
	count += 1
	if count > 4096:
		_failed("REQUEST_LIMIT", visit)
		return {}
	var frame := (JSON.stringify({"protocol_version": Protocol.VERSION, "type": "request", "request_id": pending.request_id, "op": op, "payload": payload}) + "\n").to_utf8_buffer()
	deadline = Time.get_ticks_msec() + 20000
	last_at = Time.get_ticks_msec()
	if not channel.send(frame):
		_failed("WRITE_FAILED", visit)
		return {}
	var result: Dictionary = await reply_result
	return result if visit == generation else {}

func _process(_delta: float) -> void:
	if channel != null: channel.poll()
	if connected_ok and not pending.is_empty() and deadline != 0 and Time.get_ticks_msec() >= deadline:
		_failed("REQUEST_TIMEOUT", generation)

func _frame(bytes: PackedByteArray, visit: int) -> void:
	if visit != generation: return
	var value := Protocol.decode(bytes)
	if Protocol.version_error(value):
		_failed("UNSUPPORTED_VERSION", visit)
		return
	if not Protocol.response(value):
		_failed("INVALID_MESSAGE", visit)
		return
	if value.status == "error" and value.request_id == null:
		_failed(value.error.code, visit)
		return
	if pending.is_empty() or value.request_id != pending.request_id or value.op != pending.op:
		_failed("CORRELATION_ERROR", visit)
		return
	pending = {}
	deadline = 0
	next_at = Time.get_ticks_msec() + spacing_ms
	reply_result.emit(value)

func _failed(code: String, visit: int) -> void:
	if visit != generation: return
	last_failure = code
	close()
	lost.emit(code)
