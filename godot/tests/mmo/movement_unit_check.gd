extends SceneTree
const Protocol = preload("res://scripts/mmo/protocol_v4.gd")
const Adapter = preload("res://scripts/ui/move_input.gd")
const Platform = preload("res://scripts/presentation/platform_world.gd")
var failures: Array[String] = []
var checks := 0

class FakeClient extends Node:
	signal move_rejected(code: String)
	signal state_changed(state: String)
	var state := "READY"
	var intents: Array[String] = []
	func move(direction: String) -> bool:
		if state != "READY": return false
		intents.append(direction)
		state = "MOVING"
		state_changed.emit(state)
		return true
	func stage(value: String) -> void:
		state = value
		state_changed.emit(value)

func _initialize() -> void:
	start.call_deferred()

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures.append(reason)

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func start() -> void:
	var receipt := {"epoch":"e1", "zone_id":"city/apartment", "revision":2, "player_id":"p1"}
	var reply := {"protocol_version":4,"type":"response","request_id":"r5","op":"move","status":"ok","data":receipt,"error":null}
	check(Protocol.response(reply), "VALID_RECEIPT_SCHEMA")
	for field in ["epoch", "zone_id", "revision", "player_id"]:
		var bad := reply.duplicate(true)
		bad.data.erase(field)
		check(not Protocol.response(bad), "MISSING_" + field)
	for value in [0, -1, true, "2", 2.0, null]:
		var bad := reply.duplicate(true)
		bad.data.revision = value
		check(not Protocol.response(bad), "BAD_REVISION")
	var extra := reply.duplicate(true)
	extra.data.x = 51
	check(not Protocol.response(extra), "RECEIPT_CANNOT_SET_X")
	var client := FakeClient.new()
	root.add_child(client)
	var adapter := Adapter.new()
	adapter.client = client
	root.add_child(adapter)
	adapter.set_process(false)
	key(KEY_D, true)
	adapter._process(0.01)
	check(client.intents.is_empty(), "FRESH_WORLD_REQUIRES_RELEASE")
	key(KEY_D, false)
	adapter._process(0.01)
	key(KEY_D, true)
	adapter._process(0.01)
	check(client.intents == ["right"], "PHYSICAL_D")
	for i in range(1000): adapter._process(1.0)
	check(client.intents.size() == 1, "HOLD_NO_BACKLOG")
	key(KEY_D, false)
	adapter._process(0.01)
	client.stage("READY")
	adapter._process(0.01)
	check(client.intents.size() == 1, "RELEASE_BEFORE_REPLY_NO_REPLAY")
	key(KEY_A, true)
	key(KEY_D, true)
	adapter._process(0.01)
	check(client.intents.size() == 1, "OPPOSING_KEYS_CANCEL")
	key(KEY_D, false)
	adapter._process(0.01)
	check(client.intents == ["right", "left"], "CURRENT_DIRECTION_REPLACES_OLD_INTENT")
	client.stage("READY")
	client.move_rejected.emit("RATE_LIMITED")
	for i in range(100): adapter._process(1.0)
	check(client.intents.size() == 2, "REJECTION_REQUIRES_RELEASE")
	key(KEY_A, false)
	adapter._process(0.01)
	key(KEY_RIGHT, true)
	adapter._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	adapter._process(0.01)
	adapter._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	adapter._process(0.01)
	check(client.intents.size() == 2, "FOCUS_REQUIRES_RELEASE")
	key(KEY_RIGHT, false)
	adapter._process(0.01)
	key(KEY_RIGHT, true)
	adapter._process(0.01)
	check(client.intents == ["right", "left", "right"], "ARROW_INPUT")
	client.stage("RESYNCING")
	client.stage("READY")
	adapter._process(0.01)
	check(client.intents.size() == 3, "RESYNC_DOES_NOT_REPLAY_HOLD")
	key(KEY_RIGHT, false)
	adapter._process(0.01)
	adapter.queue_free()
	client.queue_free()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(458,116)
	root.add_child(viewport)
	var platform := Platform.new()
	viewport.add_child(platform)
	platform.set_process(false)
	var map := {"schema_version":1,"map_id":"city/apartment","content_version":1,"min_x":0,"max_x":100,"spawn_x":50,"units_per_meter":1,"content_hash":"4f465435cbb8eb3e5154a4776be29e7aee4f73376e00fb26299bfbf0cfcd361b"}
	var view := {"map":{"map_id":map.map_id,"content_version":1,"content_hash":map.content_hash},"confirmed_local_x":50}
	check(platform.project(map,view) and platform.sprite.position.x == 432, "INITIAL_CONFIRMED_SPAWN")
	view.confirmed_local_x = 51
	platform.project(map,view)
	check(platform.sprite.position.x == 432, "NO_SNAP_OR_PREDICTION")
	platform._process(0.01)
	check(platform.sprite.position.x > 432 and platform.sprite.position.x < 440, "SMOOTH_CONFIRMED_TARGET")
	platform._process(0.1)
	check(platform.sprite.position.x == 440 and platform.sprite.texture == platform.WALK_RIGHT, "RIGHT_ANIMATION_AND_TARGET")
	platform.sprite.position.x = -99999
	platform._process(0)
	check(platform.sprite.position.x == 440 and view.confirmed_local_x == 51, "SPRITE_TAMPER_NOT_AUTHORITY")
	view.confirmed_local_x = 0
	platform.project(map,view)
	platform._process(100)
	check(platform.sprite.position.x == 32 and platform.sprite.texture == platform.WALK_LEFT, "LEFT_BOUND_AND_ANIMATION")
	view.confirmed_local_x = 100
	platform.project(map,view)
	platform._process(100)
	check(platform.sprite.position.x == 832, "RIGHT_BOUND_NO_OVERSHOOT")
	viewport.queue_free()
	print(JSON.stringify({"suite":"movement","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
