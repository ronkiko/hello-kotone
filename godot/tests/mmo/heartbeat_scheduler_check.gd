extends SceneTree
const Protocol = preload("res://scripts/mmo/protocol_v5.gd")
var checks := 0
var failures: Array[String] = []
class FakeChannel extends RefCounted:
	var sent: Array = []
	func poll() -> void: pass
	func close() -> void: pass
	func send(frame: PackedByteArray) -> bool:
		sent.append(JSON.parse_string(frame.get_string_from_utf8()))
		return true

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func response(op: String, data: Dictionary) -> Dictionary:
	return {"protocol_version":4,"type":"response","request_id":"r1","op":op,"status":"ok","data":data,"error":null}

func _initialize() -> void:
	start.call_deferred()

func start() -> void:
	var policy := {"min_request_interval_ms":120,"idle_timeout_ms":600,"keepalive_interval_ms":200}
	check(Protocol.response(response("session_rules",policy)),"VALID_HOST_POLICY")
	for item in [["min_request_interval_ms",0],["min_request_interval_ms",true],["min_request_interval_ms",60001],["idle_timeout_ms",0],["idle_timeout_ms",true],["idle_timeout_ms",3600001],["keepalive_interval_ms",0],["keepalive_interval_ms",true],["keepalive_interval_ms",120],["keepalive_interval_ms",301],["keepalive_interval_ms",600],["keepalive_interval_ms",200.0]]:
		var bad: Dictionary = policy.duplicate()
		bad[item[0]] = item[1]
		check(not Protocol.response(response("session_rules",bad)),"INVALID_HOST_POLICY")
	check(Protocol.response(response("ping",{"pong":true})),"VALID_PONG")
	for data in [{"pong":false},{"pong":1},{},{"pong":true,"revision":1}]:
		check(not Protocol.response(response("ping",data)),"STRICT_PONG")
	var client: Node = root.get_node("MmoClient")
	var channel := FakeChannel.new()
	client._channel = channel
	client._session_rules = policy
	client._world_rules = {"movement":{"min_move_interval_ms":200}}
	client._request_interval_ms = 121
	client.state = "READY"
	client._last_request_at = -10000
	client._process(0)
	check(channel.sent.size() == 1 and channel.sent[0].op == "ping" and client.state == "READY", "IDLE_PING_FREE_SLOT")
	var before: Dictionary = client._pending.duplicate()
	for i in range(1000): client._process(0)
	check(channel.sent.size() == 1 and client._pending == before and not client.move("right"),"SINGLE_PENDING_PING_NO_BACKLOG")
	client._on_frame(JSON.stringify(response("ping",{"pong":true})).to_utf8_buffer())
	check(client.state == "READY" and client._pending.is_empty(),"PONG_RELEASES_SLOT")
	client._next_request_at = 0
	client._last_request_at = -10000
	check(client.move("right"),"HUMAN_MOVE_SCHEDULED")
	client._process(0)
	check(channel.sent.size() == 2 and channel.sent[1].op == "move", "SCHEDULED_MOVE_NOT_DISPLACED_BY_PING")
	client._scheduled = {}
	client._pending = {}
	client.state = "READY"
	client._next_request_at = 0
	client._last_request_at = Time.get_ticks_msec()
	client._process(0)
	check(channel.sent.size() == 2,"ORDINARY_REQUEST_ACTIVITY_DEFERS_PING")
	for state in ["RESYNCING","MOVING","LOGGING_OUT","FAILED","DISCONNECTED","CONNECTING_GAME"]:
		client.state = state
		client._last_request_at = -10000
		client._process(0)
		check(channel.sent.size() == 2,"NO_PING_IN_"+state)
	client.disconnect_world()
	check(client._session_rules.is_empty() and client._scheduled.is_empty() and client._pending.is_empty(),"CLOSE_CLEARS_HEARTBEAT")
	print(JSON.stringify({"suite":"recovery","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
