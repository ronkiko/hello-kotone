extends SceneTree
## Session generation/callback cancellation checks without a server.
var checks := 0
var failures: Array[String] = []
var client: Node
var cancel_state := ""

func _initialize() -> void:
	start.call_deferred()

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures.append(reason)

func cancel(value: String) -> void:
	if value == cancel_state:
		client.disconnect_world()

func start() -> void:
	client = root.get_node("MmoClient")
	check(not client.reconnect_world() and client.state == "IDLE", "NO_ENDPOINT_NO_RECONNECT")
	client.state_changed.connect(cancel)
	cancel_state = "CONNECTING_LOGIN"
	client.connect_world("127.0.0.1", 21060, "player2")
	check(client.state == "DISCONNECTED" and client._channel._closed and client._scheduled.is_empty(), "CANCEL_DURING_OPEN_DOES_NOT_REOPEN_CHANNEL")
	var endpoint: Dictionary = client.login_endpoint
	endpoint.nickname = "player3"
	check(client.login_endpoint.nickname == "player2", "ENDPOINT_DEFENSIVE_COPY")
	client.connect_world("invalid address",21060,"player1")
	check(client.state == "FAILED" and client.last_error.code == "INVALID_CONFIG" and client.login_endpoint.nickname == "player2", "INVALID_CONFIG_DOES_NOT_REPLACE_LAST_VALID_ENDPOINT")
	cancel_state = "AUTHORIZING"
	client.reconnect_world()
	var old: RefCounted = client._channel
	old.connected.emit()
	check(client.state == "DISCONNECTED" and old._closed and client._scheduled.is_empty(), "CANCEL_DURING_CONNECTED_DOES_NOT_SCHEDULE_LOGIN")
	cancel_state = ""
	client.reconnect_world()
	var before: int = client._connection_generation
	check(not client.reconnect_world() and client._connection_generation == before, "BUSY_RECONNECT_REJECTED")
	old.connected.emit()
	old.failed.emit("DISCONNECTED")
	old.frame_received.emit("{}".to_utf8_buffer())
	check(client.state == "CONNECTING_LOGIN" and client._connection_generation == before and client._scheduled.is_empty(), "OLD_GENERATION_CANNOT_FAIL_OR_SCHEDULE_NEW_SESSION")
	client.disconnect_world()
	print(JSON.stringify({"suite":"recovery","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
