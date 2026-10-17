extends Node
## Isolated loopback candidate transport; no auth, session or gameplay authority.
signal closed
signal connected
signal disconnected(reason: String)
signal frame_received(frame: Dictionary)
signal pong_received(nonce: PackedByteArray, rtt_usec: int)
signal ping_failed(nonce: PackedByteArray, reason: String)

const API_VERSION: int = 1
const Codec = preload("soulworker_codec.gd")
# Project-specific commands in the canonical Go wire registry, not legacy opcodes.
const PING_OPCODE: int = 0xfe01
const PONG_OPCODE: int = 0xfe02
const PING_TIMEOUT_USEC: int = 1000000
const MAX_PING_NONCES: int = 256 # bounded diagnostic client lifetime replay guard
const IO_TIMEOUT_MS: int = 2000 # fixed smoke bounds, not production settings
var _socket: StreamPeerTCP = StreamPeerTCP.new()
var _codec = Codec.new()
var _closed: bool = false
var _active: bool = false
var _connected: bool = false
var _tx := PackedByteArray()
var _read_started: int = 0
var _write_started: int = 0
var _pending_ping := PackedByteArray()
var _ping_started_usec: int = 0
var _used_ping_nonces: Dictionary = {}

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

# Nonce is the eight-byte big-endian representation of a uint64. Byte arrays
# cover the complete unsigned range without Godot's signed-int64 limitation.
func ping(nonce: PackedByteArray) -> int:
    if _closed or not _connected:
        return ERR_UNAVAILABLE
    if nonce.size() != 8:
        return ERR_INVALID_DATA
    if not _pending_ping.is_empty():
        return ERR_BUSY
    var key: String = nonce.hex_encode()
    if _used_ping_nonces.has(key):
        return ERR_ALREADY_EXISTS
    if _used_ping_nonces.size() >= MAX_PING_NONCES:
        return ERR_OUT_OF_MEMORY
    var error: int = _enqueue_frame(1, PING_OPCODE, nonce)
    if error != OK:
        return error
    _used_ping_nonces[key] = true
    _pending_ping = nonce.duplicate()
    _ping_started_usec = Time.get_ticks_usec()
    return OK

func send_frame(sender: int, opcode: int, payload: PackedByteArray) -> int:
    if opcode == PING_OPCODE or opcode == PONG_OPCODE:
        return ERR_INVALID_PARAMETER # use ping(), so completion is correlated
    return _enqueue_frame(sender, opcode, payload)

func _enqueue_frame(sender: int, opcode: int, payload: PackedByteArray) -> int:
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
    if not _pending_ping.is_empty() and Time.get_ticks_usec() - _ping_started_usec >= PING_TIMEOUT_USEC:
        _drop("ping_timeout")
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
            if frame.opcode == PONG_OPCODE:
                if frame.payload.size() != 8:
                    _drop("malformed_pong")
                    return
                if _pending_ping.is_empty():
                    _drop("unsolicited_pong")
                    return
                if frame.payload != _pending_ping:
                    _drop("wrong_pong_nonce")
                    return
                var nonce: PackedByteArray = _pending_ping.duplicate()
                var rtt_usec: int = Time.get_ticks_usec() - _ping_started_usec
                _pending_ping.clear()
                pong_received.emit(nonce, rtt_usec)
            elif (frame.opcode >> 8) == (PING_OPCODE >> 8):
                _drop("unexpected_extension_opcode")
                return
            else:
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
    if not _pending_ping.is_empty():
        var failed_nonce: PackedByteArray = _pending_ping.duplicate()
        _pending_ping.clear()
        ping_failed.emit(failed_nonce, reason)
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
