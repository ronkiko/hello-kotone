extends SceneTree
const MAP = {"schema_version":1,"map_id":"city/apartment","content_version":1,"min_x":0,"max_x":100,"spawn_x":50,"units_per_meter":1,"content_hash":"4f465435cbb8eb3e5154a4776be29e7aee4f73376e00fb26299bfbf0cfcd361b"}
var checks := 0
var failures: Array[String] = []
var client: Node
class FakeChannel extends RefCounted:
	var sent: Array = []
	func poll() -> void: pass
	func close() -> void: pass
	func send(frame: PackedByteArray) -> bool:
		sent.append(preload("res://scripts/mmo/protocol_v6.gd").decode(frame.slice(0,frame.size()-1)))
		return true
func _initialize() -> void:
	start.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func ready() -> FakeChannel:
	client._clear_session()
	client.last_error = {}
	client._channel = FakeChannel.new()
	client.state = "READY"
	client.player_id = "p1"
	client.session_id = "s1"
	client.map_document = MAP.duplicate(true)
	client._world_rules = {"identity":world_bootstrap("e1").identity,"movement":{"step_units":1,"min_move_interval_ms":200}}
	client._session_rules = {"min_request_interval_ms":50,"idle_timeout_ms":120000,"keepalive_interval_ms":40000}
	client._request_interval_ms = 51
	client._last_request_at = Time.get_ticks_msec()
	client._next_request_at = 0
	client._request_count = 0
	var snapshot := {"epoch":"e1","revision":1,"map":{"map_id":MAP.map_id,"content_version":1,"content_hash":MAP.content_hash},"players":[{"player_id":"p1","nickname":"player1","zone_id":MAP.map_id,"x":50}]}
	check(client.world_session.bind(world_bootstrap(snapshot.epoch)) and client.world_replica.start(snapshot,"p1","player1") and client.world_replica.install_map(MAP), "FRESH_TEST_SESSION")
	return client._channel
func ack(data: Dictionary = {}) -> void:
	var value := {"epoch":"e1","zone_id":MAP.map_id,"player_id":"p1","input_seq":1,"x":50}
	value.merge(data,true)
	client._on_frame(JSON.stringify({"protocol_version":6,"type":"response","request_id":"r1","op":"input","status":"ok","data":value,"error":null}).to_utf8_buffer())
func start() -> void:
	client = root.get_node("MmoClient")
	client.set_process(false)
	var channel := ready()
	client._next_request_at = Time.get_ticks_msec() + 10000
	client.set_input("right")
	check(client._scheduled.payload.direction == "right", "PRESS_SCHEDULED_NOT_SENT")
	client.set_input("stop")
	for i in range(1000): client._process(0)
	check(client.state == "READY" and client._scheduled.is_empty() and channel.sent.is_empty(), "RELEASE_CANCELS_UNSENT_PRESS_NO_REPLAY")
	client.set_input("right")
	client.set_input("left")
	client._next_request_at = 0
	client._process(0)
	check(channel.sent.size() == 1 and channel.sent[0].payload == {"input_seq":1,"direction":"left"}, "UNSENT_REVERSAL_COALESCES_LATEST_DESIRE")
	client.set_input("stop")
	check(client._pending.payload.direction == "left" and client._scheduled.is_empty(), "PENDING_INPUT_NEVER_REWRITTEN_OR_REPLAYED")
	ack()
	check(client._server_input == "left" and client._scheduled.payload == {"input_seq":2,"direction":"stop"}, "PENDING_RELEASE_SENDS_FRESH_STOP_AFTER_ACK")
	channel = ready()
	client._scheduled = {"op":"ping","payload":{}}
	client.set_input("right")
	check(client._scheduled.op == "input", "HUMAN_INPUT_PREEMPTS_UNSENT_PING")
	for bad in [{"input_seq":2},{"epoch":"old"},{"zone_id":"city/street"},{"player_id":"p2"},{"x":51}]:
		channel = ready()
		client.set_input("right")
		client._process(0)
		ack(bad)
		check(client.state == "FAILED" and client.last_error.code == "INPUT_BASELINE_MISMATCH" and client.last_error.operation == "input" and client.last_error.outcome_unknown, "MALFORMED_ACK_KEEPS_UNKNOWN_MUTATION_CONTEXT")
	channel = ready()
	client.set_input("right")
	client._process(0)
	var accepted: Array = []
	var on_accepted := func(seq: int, direction: String, x: int): accepted.append([seq,direction,x])
	var cancel_ready := func(state: String):
		if state == "READY": client.disconnect_world()
	client.input_accepted.connect(on_accepted)
	client.state_changed.connect(cancel_ready)
	ack()
	check(client.state == "DISCONNECTED" and accepted.is_empty(), "READY_CALLBACK_CANCELLATION_FENCES_OLD_ACK_SIGNAL")
	client.state_changed.disconnect(cancel_ready)
	client.input_accepted.disconnect(on_accepted)
	channel = ready()
	client.set_input("right")
	client._process(0)
	var replies: Array = []
	var cancel_accepted := func(_seq: int,_direction: String,_x: int): client.disconnect_world()
	var on_reply := func(op: String,_data: Dictionary): replies.append(op)
	client.input_accepted.connect(cancel_accepted)
	client.response_received.connect(on_reply)
	ack()
	check(client.state == "DISCONNECTED" and replies.is_empty(), "ACCEPT_CALLBACK_CANCELLATION_FENCES_OLD_RESPONSE_SIGNAL")
	client.input_accepted.disconnect(cancel_accepted)
	client.response_received.disconnect(on_reply)
	# Exercise the shipped UI: a cancelled unsent tap still settles local prediction.
	channel = ready()
	client._next_request_at = Time.get_ticks_msec() + 10000
	var world: Control = load("res://scenes/mmo/world.tscn").instantiate()
	root.add_child(world)
	world.platform.set_process(false)
	world.input_adapter.set_process(false)
	world.input_adapter._set_locomotion_intent(1)
	world.platform._process(.04)
	check(world.platform.sprite.position.x > world.platform.server_to_pixel(50), "UNSENT_TAP_STARTS_LOCAL_PREDICTION")
	world.input_adapter._set_locomotion_intent(0)
	world.platform._process(.5)
	world.platform._process(0)
	check(client._scheduled.is_empty() and channel.sent.is_empty() and is_equal_approx(world.platform.sprite.position.x,world.platform.server_to_pixel(50)) and world.platform.sprite.texture == world.platform.IDLE, "CANCELLED_UNSENT_TAP_MAGNETS_TO_CONFIRMED_IDLE")
	world.queue_free()
	await process_frame
	client.disconnect_world()
	print(JSON.stringify({"suite":"movement","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func world_bootstrap(epoch: String = "e1") -> Dictionary:
	return {"identity": {"game_card_id": "hello-kotone", "realm_id": "local", "realm_instance_id": epoch}, "capabilities": ["input", "logout", "map", "state", "world_rules"]}
