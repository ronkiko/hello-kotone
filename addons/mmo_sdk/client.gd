extends Node
## Local SDK foundation. HTTP/WebSocket operations and remote protocol are not
## implemented by this patch. Local health never represents a server response.
signal closed

const API_VERSION: int = 1
var _http: HTTPRequest
var _socket: WebSocketPeer
var _closed: bool = false

func _init() -> void:
    _http = HTTPRequest.new()
    _http.name = "HttpTransport"
    add_child(_http)
    _socket = WebSocketPeer.new()

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
        "http_backend": _http.get_class(),
        "http_state": _http.get_http_client_status(),
        "socket_backend": _socket.get_class(),
        "socket_state": _socket.get_ready_state(),
    }

func close() -> void:
    if _closed:
        return
    _closed = true
    _http.cancel_request()
    _http.queue_free()
    _http = null
    # No connection is opened in 10.02; releasing the native peer is sufficient.
    _socket = null
    closed.emit()

func _exit_tree() -> void:
    close()
