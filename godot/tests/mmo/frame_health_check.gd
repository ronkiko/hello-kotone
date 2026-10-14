extends SceneTree
const Health = preload("res://scripts/mmo/frame_health.gd")
const Fixtures = preload("res://tests/mmo/replica_check.gd")
const Loop = preload("res://scripts/presentation/visual_stall_loop.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var healthy := Health.new()
	var now := 0
	check(healthy.poll(10000000) == 4 and healthy.last_usec == -1, "starts only on accepted world motion")
	for index in range(100):
		now += 50000 + (index % 5 - 2) * 3000
		healthy.accepted(now)
	check(healthy.gaps.size() == 64 and healthy.max_wait > healthy.min_wait, "bounded healthy jitter baseline")
	for count in range(4, -1, -1):
		var p := 0.0 if count == 4 else (1.0 if count == 0 else (4.0 - count + 0.2) / 4.0)
		var elapsed := healthy.min_wait + p * (healthy.max_wait - healthy.min_wait)
		check(healthy.poll(now + int(elapsed)) == count, "relative bars " + str(count))
	var maximum: float = healthy.max_wait
	var history := healthy.gaps.duplicate()
	healthy.accepted(now + 10000000)
	check(healthy.bars == 4 and healthy.max_wait == maximum and healthy.gaps == history, "first resumed frame restores green without learning silence")
	var batched := Health.new()
	for index in range(100): batched.accepted(index * 10)
	check(batched.min_wait >= Health.NOMINAL_GAP_USEC * 2.0 and batched.max_wait >= Health.NOMINAL_GAP_USEC * 8.0, "coalesced delivery cannot collapse healthy cadence")
	var slow := Health.new()
	for index in range(100): slow.accepted(index * 90000)
	check(slow.max_wait > healthy.max_wait, "independent relative cadence, no absolute freeze deadline")
	var bounded := Health.new()
	var clock := 0
	for index in range(256):
		clock += int(bounded.min_wait * 0.9)
		bounded.accepted(clock)
	check(bounded.max_wait <= Health.NOMINAL_GAP_USEC * 16.0 and bounded.min_wait <= Health.NOMINAL_GAP_USEC * 4.0, "degrading cadence cannot expand beyond relative nominal caps")
	var replica := preload("res://scripts/mmo/world_replica.gd").new()
	replica.world_session.bind({"identity":{"game_card_id":"hello-kotone","realm_id":"local","realm_instance_id":"e1"},"capabilities":["control_set","logout","map","state","world_rules"]})
	replica.start({"epoch":"e1","revision":1,"map":{"map_id":Fixtures.MAP.map_id,"content_version":1,"content_hash":Fixtures.MAP.content_hash},"players":[Fixtures.player()]}, "p1", "player1")
	replica.install_map(Fixtures.MAP)
	var event := {"protocol_version":9,"type":"event","event":"motion_frame","epoch":"e1","zone_id":Fixtures.MAP.map_id,"revision":5,"data":{"realm_instance_id":"e1","zone_package_id":Fixtures.MAP.map_id,"zone_generation":1,"frame_seq":1,"realm_tick":4,"players":[{"player_id":"p1","position_mm":50000,"velocity_mm_s":0,"facing":-1,"last_applied_control_seq":1,"control_started_tick":0,"contacts":[],"contact_delta_velocity_mm_s":0,"contact_response_facing":0,"contact_response_tick":0,"contact_response_contacts":[],"contact_impact_sources":[]}]}}
	check(replica.apply_event(event), "ordinary frame accepted")
	var next := event.duplicate(true)
	next.data.zone_generation = 3
	next.data.frame_seq += 1
	next.data.realm_tick += 50
	next.revision += 1
	next.data.players[0].last_applied_control_seq = 0
	next.data.players[0].position_mm += 20
	var joined := {"protocol_version":9,"type":"event","event":"joined","epoch":"e1","zone_id":Fixtures.MAP.map_id,"revision":6,"data":{"player":Fixtures.player("p2", "peer", 50400)}}
	check(replica.apply_event(joined), "known peer in resumed damage scope")
	var damage := {"protocol_version":9,"type":"event","event":"damage_resolved","epoch":"e1","zone_id":Fixtures.MAP.map_id,"revision":7,"data":{"event_id":"damage_1","event_seq":1,"zone_generation":3,"realm_tick":54,"target_entity_id":"p1","source_entity_id":"p2","position_mm":50000,"impact_impulse_g_mm_s":37900000,"damage":8,"cause":"body_collision"}}
	check(replica.apply_event(damage) and replica.view().zone_generation == 1, "reliable new-incarnation fact may precede sample without advancing motion fence")
	next.revision = 8
	var peer_sample: Dictionary = next.data.players[0].duplicate(true)
	peer_sample.player_id = "p2"
	peer_sample.position_mm = 50400
	next.data.players.append(peer_sample)
	check(replica.apply_event(next) and replica.view().zone_generation == 3, "ordinary new generation resets control fence")
	check(not replica.apply_event(event) and not replica.view().reconnect_required, "late old incarnation cannot kill recovered stream")
	check(not replica.apply_event(next), "duplicate cannot refresh watchdog")
	var client: Node = root.get_node("MmoClient")
	client.set_process(false)
	client._clear_session()
	client.state = "READY"
	client._world_rules = {"movement":Fixtures.rules()}
	var platform: Node = load("res://scripts/presentation/platform_world.gd").new()
	root.add_child(platform)
	platform.set_process(false)
	platform.set_physics_process(false)
	platform.set_movement_rules(client._world_rules)
	var p := Fixtures.player()
	check(platform.project(Fixtures.MAP, {"map":{"map_id":Fixtures.MAP.map_id,"content_version":1,"content_hash":Fixtures.MAP.content_hash},
		"players":{"p1":p},"local_player_id":"p1","confirmed_local_position_mm":50000}), "native actor installed")
	platform.character_root.position.y = -37.125
	platform.character_root.velocity = Vector2(100, 100)
	var pose: Vector2 = platform.character_root.position
	var camera: Vector2 = platform.camera.position
	var anchor: Vector2 = platform.sprite.position
	var frames: SpriteFrames = platform.sprite.sprite_frames
	platform.sprite.play(&"walk_right")
	platform.sprite.frame = 3
	client.state = "MOVING"
	client._scheduled = {"op":"control_set","payload":{"zone_generation":1,"control_seq":1,"drive":1,"facing":1}}
	client._set_frame_health(0)
	check(client.state == "READY" and client._scheduled.is_empty(), "watchdog purge cannot leave empty MOVING slot")
	check(client.visual_stalled and not client.set_control(1, 1), "stall withholds control")
	for index in range(60):
		platform._physics_process(1.0 / 60.0)
		platform._process(1.0 / 60.0)
	check(platform.character_root.position == pose and platform.camera.position == camera and platform.sprite.position == anchor,
		"midair exact XY/camera/root anchor freeze")
	check(platform.sprite.sprite_frames.get_frame_count(&"stall") in [2,3,4] and platform.sprite.is_playing(), "native current-action tiny loop stays alive")
	client._set_frame_health(4)
	check(not platform._visual_stalled and platform.sprite.sprite_frames == frames, "first frame thaws original SpriteFrames")
	platform.queue_free()
	client.disconnect_world()
	print(JSON.stringify({"suite":"frame-health","checks":checks,"failures":failures,"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
