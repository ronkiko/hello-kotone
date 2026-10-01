extends RefCounted
## One bounded, non-blocking TCP stream. Call poll() from the render loop.

signal connected
signal frame_received(frame: PackedByteArray)
signal failed(code: String)

const MAX_FRAME_BYTES := 65536
const READ_BUDGET := 16384
var connect_timeout_ms := 5000
var write_timeout_ms := 5000
var frame_timeout_ms := 10000
var _peer := StreamPeerTCP.new()
var _closed := true
var _connecting := false
var _resolver := IP.RESOLVER_INVALID_ID
var _port := 0
var _connect_deadline := 0
var _write_deadline := 0
var _frame_deadline := 0
var _receive := PackedByteArray()
var _send := PackedByteArray()
var _send_offset := 0

func open(host: String, port: int) -> void:
	close()
	_closed = false
	_connecting = true
	_port = port
	_connect_deadline = Time.get_ticks_msec() + connect_timeout_ms
	# Synchronous hostname resolution would stall Godot's main thread.
	if host.is_valid_ip_address():
		_connect_ip(host)
	else:
		_resolver = IP.resolve_hostname_queue_item(host)
		if _resolver == IP.RESOLVER_INVALID_ID:
			_fail("DNS_FAILED")

func _connect_ip(address: String) -> void:
	if _peer.connect_to_host(address, _port) != OK:
		_fail("CONNECT_FAILED")

func close() -> void:
	_closed = true
	_connecting = false
	if _resolver != IP.RESOLVER_INVALID_ID:
		IP.erase_resolve_item(_resolver)
		_resolver = IP.RESOLVER_INVALID_ID
	_peer.disconnect_from_host()
	_receive.clear()
	_send.clear()
	_send_offset = 0
	_frame_deadline = 0

func send(frame: PackedByteArray) -> bool:
	if _closed or _connecting or not _send.is_empty() or frame.size() > MAX_FRAME_BYTES:
		return false
	_send = frame
	_send_offset = 0
	_write_deadline = Time.get_ticks_msec() + write_timeout_ms
	return true

func poll() -> void:
	if _closed:
		return
	var now := Time.get_ticks_msec()
	if _connecting and now >= _connect_deadline:
		_fail("CONNECT_TIMEOUT")
		return
	if _resolver != IP.RESOLVER_INVALID_ID:
		var resolver_state := IP.get_resolve_item_status(_resolver)
		if resolver_state == IP.RESOLVER_STATUS_WAITING:
			return
		var address := IP.get_resolve_item_address(_resolver)
		IP.erase_resolve_item(_resolver)
		_resolver = IP.RESOLVER_INVALID_ID
		if resolver_state != IP.RESOLVER_STATUS_DONE or address.is_empty():
			_fail("DNS_FAILED")
			return
		_connect_ip(address)
		if _closed:
			return
	var poll_error := _peer.poll()
	var peer_state := _peer.get_status()
	if peer_state == StreamPeerTCP.STATUS_CONNECTING:
		return
	if peer_state != StreamPeerTCP.STATUS_CONNECTED or poll_error != OK:
		_fail("CONNECT_FAILED" if _connecting else ("TRUNCATED_FRAME" if not _receive.is_empty() else "DISCONNECTED"))
		return
	if _connecting:
		_connecting = false
		_peer.set_no_delay(true)
		connected.emit()
		if _closed:
			return
	if not _send.is_empty():
		if now >= _write_deadline:
			_fail("WRITE_TIMEOUT")
			return
		var sent := _peer.put_partial_data(_send.slice(_send_offset))
		if sent[0] != OK:
			_fail("WRITE_FAILED")
			return
		_send_offset += sent[1]
		if _send_offset == _send.size():
			_send.clear()
			_send_offset = 0
	if _frame_deadline != 0 and now >= _frame_deadline:
		_fail("FRAME_TIMEOUT")
		return
	var budget := READ_BUDGET
	while not _closed and budget > 0 and _peer.get_available_bytes() > 0:
		var received := _peer.get_partial_data(mini(4096, mini(budget, _peer.get_available_bytes())))
		if received[0] != OK:
			_fail("READ_FAILED")
			return
		var bytes: PackedByteArray = received[1]
		if bytes.is_empty():
			return
		budget -= bytes.size()
		for byte in bytes:
			if _closed:
				return
			if _receive.is_empty():
				_frame_deadline = now + frame_timeout_ms
			if byte == 10:
				var frame := _receive
				_receive = PackedByteArray()
				_frame_deadline = 0
				frame_received.emit(frame)
			else:
				_receive.append(byte)
				if _receive.size() >= MAX_FRAME_BYTES:
					_fail("FRAME_TOO_LARGE")
					return

func _fail(code: String) -> void:
	close()
	failed.emit(code)
