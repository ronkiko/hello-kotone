extends Node
## Isolated loopback candidate transport; no auth, session or gameplay authority.
signal closed
signal connected
signal disconnected(reason: String)
signal frame_received(frame: Dictionary)

const API_VERSION: int = 1
const Codec = preload("soulworker_codec.gd")
const IO_TIMEOUT_MS: int = 2000 # fixed smoke bounds, not production settings
var _socket: StreamPeerTCP = StreamPeerTCP.new()
var _codec = Codec.new()
var _closed: bool = false
var _active: bool = false
var _connected: bool = false
var _tx := PackedByteArray()
var _read_started: int = 0
var _write_started: int = 0

func local_health(nonce: int) -> Dictionary:
    if _closed:
        return {"error": ERR_UNAVAILABLE, "scope": "local_sdk"}
    if not is_inside_tree():
        return {"error": ERR_UNCONFIGURED, "scope": "local_sdk"}
    return {
        "error": OK,
        "scope": "local_sdk",
        "api_version": API_VERSION,
        "nonce": nonce,
        "socket_backend": _socket.get_class(),
        "socket_state": _socket.get_status(),
    }

func connect_loopback(port: int, host: String = "127.0.0.1") -> int:
    if _closed or not is_inside_tree():
        return ERR_UNAVAILABLE
    if _active:
        return ERR_ALREADY_IN_USE
    if host != "127.0.0.1" or port < 1 or port > 65535:
        return ERR_INVALID_PARAMETER
    _socket = StreamPeerTCP.new()
    _codec = Codec.new()
    var error: int = _socket.connect_to_host(host, port)
    if error != OK:
        return error
    _active = true
    _read_started = Time.get_ticks_msec()
    return OK

func send_frame(sender: int, opcode: int, payload: PackedByteArray) -> int:
    if _closed or not _connected:
        return ERR_UNAVAILABLE
    var wire: PackedByteArray = Codec.encode_frame(sender, opcode, payload)
    if wire.is_empty():
        return ERR_INVALID_DATA
    if _tx.size() + wire.size() > 2 * Codec.MAX_FRAME:
        return ERR_BUSY
    if _tx.is_empty():
        _write_started = Time.get_ticks_msec()
    _tx.append_array(wire)
    return OK

func _process(_delta: float) -> void:
    if not _active or _closed:
        return
    var error: int = _socket.poll()
    var status: int = _socket.get_status()
    if error != OK or status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
        var eof_error: int = _codec.end_of_stream()
        _drop("truncated_frame" if eof_error != OK else "peer_disconnected")
        return
    var now: int = Time.get_ticks_msec()
    if now - _read_started >= IO_TIMEOUT_MS:
        _drop("read_timeout")
        return
    if status != StreamPeerTCP.STATUS_CONNECTED:
        return
    if not _connected:
        _connected = true
        _socket.set_no_delay(true)
        connected.emit()
        if _closed or not _active:
            return
    if not _tx.is_empty():
        if now - _write_started >= IO_TIMEOUT_MS:
            _drop("write_timeout")
            return
        var sent: Array = _socket.put_partial_data(_tx)
        if sent[0] != OK:
            _drop("write_error")
            return
        _tx = _tx.slice(int(sent[1]))
    # Bound work per SceneTree frame; remaining bytes wait in the kernel.
    var available: int = mini(_socket.get_available_bytes(), Codec.MAX_FRAME)
    if available > 0:
        var received: Array = _socket.get_partial_data(available)
        if received[0] != OK:
            _drop("read_error")
            return
        var decoded: Dictionary = _codec.feed(received[1])
        if decoded.error != OK:
            _drop("malformed_frame")
            return
        for frame in decoded.frames:
            _read_started = now
            frame_received.emit(frame)
            if _closed or not _active:
                return

func _drop(reason: String) -> void:
    if not _active:
        return
    _active = false
    _connected = false
    _tx.clear()
    _socket.disconnect_from_host()
    disconnected.emit(reason)

func close() -> void:
    if _closed:
        return
    _closed = true
    _drop("local_close")
    _socket = null
    closed.emit()

func _exit_tree() -> void:
    close()
