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
	var locomotion_changes: Array[int] = []
	adapter.locomotion_intent_changed.connect(func(direction: int): locomotion_changes.append(direction))
	root.add_child(adapter)
	adapter.set_process(false)
	key(KEY_D, true)
	adapter._process(0.01)
	check(client.intents.is_empty(), "FRESH_WORLD_REQUIRES_RELEASE")
	key(KEY_D, false)
	adapter._process(0.01)
	key(KEY_D, true)
	adapter._process(0.01)
	check(client.intents == ["right"] and adapter.locomotion_intent == 1 and locomotion_changes == [1], "PHYSICAL_D_AND_HELD_INTENT")
	for i in range(1000): adapter._process(1.0)
	check(client.intents.size() == 1 and adapter.locomotion_intent == 1, "HOLD_NO_BACKLOG_BUT_INTENT_REMAINS")
	key(KEY_D, false)
	adapter._process(0.01)
	check(adapter.locomotion_intent == 0 and locomotion_changes.back() == 0, "RELEASE_IS_PRESENTATION_INTENT_NOT_MUTATION")
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
	platform.set_movement_rules({"movement":{"step_units":1,"min_move_interval_ms":200}})
	viewport.add_child(platform)
	platform.set_process(false)
	var map := {"schema_version":1,"map_id":"city/apartment","content_version":1,"min_x":0,"max_x":100,"spawn_x":50,"units_per_meter":1,"content_hash":"4f465435cbb8eb3e5154a4776be29e7aee4f73376e00fb26299bfbf0cfcd361b"}
	var view := {"map":{"map_id":map.map_id,"content_version":1,"content_hash":map.content_hash},"confirmed_local_x":50}
	check(platform.project(map,view) and platform.sprite.position.x == 432, "INITIAL_CONFIRMED_SPAWN")
	check(platform.set_local_intent(1), "LOCAL_INTENT_RIGHT")
	view.confirmed_local_x = 51
	platform.project(map,view)
	check(platform.sprite.position.x == 432, "NO_SNAP_OR_PREDICTION")
	platform._process(0.01)
	check(platform.sprite.position.x > 432 and platform.sprite.position.x < 440, "SMOOTH_CONFIRMED_TARGET")
	platform._process(0.1)
	check(platform.sprite.position.x < 440 and platform.sprite.texture == platform.WALK_RIGHT, "WALK_DURING_ACTUAL_TRAVEL")
	platform._process(0.1)
	check(platform.sprite.position.x == 440 and platform.sprite.texture == platform.WALK_RIGHT, "HELD_INTENT_KEEPS_SIDE_POSE_AT_BOUNDARY")
	check(platform.set_local_intent(0), "LOCAL_RELEASE")
	platform._process(0)
	check(platform.sprite.texture == platform.IDLE, "RELEASE_PLUS_SETTLED_RETURNS_FRONT_IDLE")
	platform.sprite.position.x = -99999
	platform._process(0)
	check(platform.sprite.position.x == 440 and view.confirmed_local_x == 51, "SPRITE_TAMPER_NOT_AUTHORITY")
	view.confirmed_local_x = 0
	platform.project(map,view)
	platform._process(100)
	check(platform.sprite.position.x == 32 and platform.sprite.texture == platform.WALK_LEFT, "LEFT_BOUND_TRAVEL")
	platform._process(0)
	check(platform.sprite.texture == platform.IDLE, "LEFT_BOUND_SETTLED_IDLE")
	view.confirmed_local_x = 100
	platform.project(map,view)
	platform._process(100)
	check(platform.sprite.position.x == 832, "RIGHT_BOUND_NO_OVERSHOOT")
	platform._process(0)
	check(platform.sprite.texture == platform.IDLE, "RIGHT_BOUND_SETTLED_IDLE")
	# Timing is derived from World cadence. A normal one-step gap has no permanent speed-up.
	check(is_equal_approx(platform.motion_profile.nominal_speed, 40.0), "WORLD_200MS_NOMINAL_SPEED")
	check(is_equal_approx(platform.motion_profile.speed_for_gap(8.0), 40.0), "ONE_STEP_EXACT_WORLD_CADENCE")
	check(platform.motion_profile.speed_for_gap(16.0) > 40.0 and platform.motion_profile.speed_for_gap(16.0) <= 50.0, "CATCH_UP_ONLY_WHEN_MORE_THAN_ONE_STEP_BEHIND")
	check(platform.set_movement_rules({"movement":{"step_units":1,"min_move_interval_ms":350}}), "WORLD_350MS_RULES")
	view.confirmed_local_x = 99
	platform.project(map,view)
	check(is_equal_approx(platform.motion_profile.nominal_speed, 8.0 / .35), "NEGOTIATED_350MS_SPEED")
	platform._process(.05)
	check(platform.sprite.texture == platform.WALK_LEFT and platform.sprite.position.x > 824, "350MS_NO_FAST_SNAP")
	var distance: float = platform.gait.walk_distance
	var frame: int = platform.sprite.frame
	platform._process(0)
	check(platform.gait.walk_distance == distance and platform.sprite.frame == frame, "NO_DISTANCE_NO_WALK_PHASE")
	platform.set_suspended(true)
	var frozen_x: float = platform.sprite.position.x
	platform._process(10)
	check(platform.sprite.position.x == frozen_x and platform.gait.walk_distance == distance and platform.sprite.frame == frame, "SUSPENDED_MOTION_AND_PHASE_FROZEN")
	platform.set_suspended(false)
	platform._process(1)
	check(platform.sprite.position.x == 824, "ARRIVAL_AT_TARGET")
	platform._process(0)
	check(platform.sprite.texture == platform.IDLE, "ARRIVAL_WITHOUT_INTENT_IDLES")
	var scaled := map.duplicate(true)
	scaled.units_per_meter = 2
	var canonical := scaled.duplicate()
	canonical.erase("content_hash")
	scaled.content_hash = JSON.stringify(canonical, "", true).sha256_text()
	view.map.content_hash = scaled.content_hash
	check(platform.project(scaled,view), "VALID_SCALED_PROFILE")
	check(is_equal_approx(platform.motion_profile.nominal_speed, 4.0 / .35), "MAP_SCALE_DERIVES_SPEED")
	var remote := preload("res://scripts/presentation/remote_player.gd").new()
	viewport.add_child(remote)
	remote.set_process(false)
	remote.configure_motion(1, 350, 2, 8.0)
	remote.project("player2", 100, 0, 200)
	remote.project("player2", 104, 0, 200)
	remote._process(.05)
	check(is_equal_approx(remote.position.x, 100 + platform.motion_profile.nominal_speed * .05) and remote.sprite.texture == platform.WALK_RIGHT, "REMOTE_USES_SAME_PROFILE")
	remote._process(1)
	check(remote.position.x == 104 and remote.sprite.texture == platform.WALK_RIGHT, "REMOTE_ARRIVAL_TRAVEL_FRAME")
	remote._process(0)
	check(remote.sprite.texture == platform.IDLE, "REMOTE_CONFIRMED_ARRIVAL_CAN_IDLE")
	# Equal visual distances give equal walk frames despite different elapsed time.
	var gait_a := preload("res://scripts/presentation/gait_animator.gd").new()
	var gait_b := preload("res://scripts/presentation/gait_animator.gd").new()
	gait_a.configure(32.0)
	gait_b.configure(32.0)
	gait_a.reset(platform.sprite)
	gait_a.update(platform.sprite,0,6,100,1,.01)
	var phase_frame: int = platform.sprite.frame
	gait_b.reset(platform.sprite)
	gait_b.update(platform.sprite,0,6,100,1,2.0)
	check(platform.sprite.frame == phase_frame and phase_frame == 1, "WALK_PHASE_DISTANCE_NOT_TIME")
	check(not platform.set_movement_rules({"movement":{"step_units":1,"min_move_interval_ms":0}}), "INVALID_MOTION_RULES_REJECTED")
	# Local trajectory separates held locomotion from the bounded one-step display target.
	var Profile := preload("res://scripts/presentation/player_motion.gd")
	var Trajectory := preload("res://scripts/presentation/local_trajectory.gd")
	var Gait := preload("res://scripts/presentation/gait_animator.gd")
	for interval in [200,350]:
		for hz in [60,144]:
			var profile := Profile.new()
			profile.configure(1, interval, 1, 8.0)
			var trajectory := Trajectory.new()
			trajectory.configure(profile, 0.0, 1000.0)
			trajectory.reset(0.0)
			trajectory.set_intent(1)
			var gait := Gait.new()
			gait.configure(profile.cycle_pixels)
			gait.reset(remote.sprite)
			var dt := 1.0 / float(hz)
			var stayed_side := true
			for step in range(1, 21):
				trajectory.retarget(float(step * 8))
				for tick in range(int(ceil(float(interval) / 1000.0 / dt))):
					var sample := trajectory.advance(dt)
					gait.update(remote.sprite,sample.before,sample.after,sample.target,sample.intent,dt)
					stayed_side = stayed_side and remote.sprite.texture == platform.WALK_RIGHT
			check(stayed_side, "HELD_INTENT_CONTINUOUS_GAIT_%dMS_%dHZ" % [interval,hz])
			var stopped_frame: int = remote.sprite.frame
			var settled := trajectory.advance(0)
			gait.update(remote.sprite,settled.before,settled.after,settled.target,settled.intent,0)
			check(remote.sprite.texture == platform.WALK_RIGHT and remote.sprite.frame == stopped_frame, "HELD_BOUNDARY_FREEZES_LEGS_NOT_FRONT_IDLE")
			trajectory.set_intent(0)
			settled = trajectory.advance(0)
			gait.update(remote.sprite,settled.before,settled.after,settled.target,settled.intent,0)
			check(remote.sprite.texture == platform.IDLE, "RELEASE_AND_SETTLED_EXACT_FRONT_IDLE")
			trajectory.set_intent(-1)
			trajectory.retarget(trajectory.visual_x - 8.0)
			var reverse := trajectory.advance(dt)
			gait.update(remote.sprite,reverse.before,reverse.after,reverse.target,reverse.intent,dt)
			check(remote.sprite.texture == platform.WALK_LEFT, "REVERSAL_FOLLOWS_ACTUAL_RENDER_DISTANCE")
	viewport.queue_free()
	print(JSON.stringify({"suite":"movement","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
