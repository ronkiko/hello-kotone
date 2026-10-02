extends SceneTree
const Replica = preload("res://scripts/mmo/world_replica.gd")
const Platform = preload("res://scripts/presentation/platform_world.gd")
var checks := 0
var failures: Array[String] = []
var document := {"schema_version":1,"map_id":"city/apartment","content_version":1,"min_x":0,"max_x":100,"spawn_x":50,"units_per_meter":1,"content_hash":"4f465435cbb8eb3e5154a4776be29e7aee4f73376e00fb26299bfbf0cfcd361b"}

func _initialize() -> void:
	start.call_deferred()

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures.append(reason)

func event(revision: int, player: Dictionary, kind: String) -> Dictionary:
	return {"protocol_version":5,"type":"event","event":kind,"epoch":"e1","zone_id":"city/apartment","revision":revision,"data":{"player_id":player.player_id} if kind == "left" else {"player":player}}

func start() -> void:
	var replica := Replica.new()
	var local := {"player_id":"p1","nickname":"player1","zone_id":"city/apartment","x":50}
	var remote := {"player_id":"p2","nickname":"player2","zone_id":"city/apartment","x":52}
	var baseline := {"epoch":"e1","revision":1,"map":{"map_id":document.map_id,"content_version":1,"content_hash":document.content_hash},"players":[local, remote]}
	check(replica.start(baseline,"p1","player1") and replica.install_map(document), "BASELINE")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(458,116)
	root.add_child(viewport)
	var platform := Platform.new()
	platform.set_movement_rules({"movement":{"step_units":1,"min_move_interval_ms":200}})
	viewport.add_child(platform)
	platform.set_process(false)
	check(platform.project(document,replica.view()), "PROJECT_SNAPSHOT")
	check(platform.remote_players.size() == 1 and not platform.remote_players.has("p1"), "EXCLUDE_LOCAL")
	var avatar: Node2D = platform.remote_players.p2
	avatar.set_process(false)
	var instance_id := avatar.get_instance_id()
	check(avatar.position.x == platform.server_to_pixel(52) and avatar.identity.text == "player2", "REMOTE_INITIAL_SNAP_LABEL")
	check(avatar.sprite.get_script() == null and avatar.get_child_count() == 2, "NO_REMOTE_CONTROLLER_INPUT_OR_NETWORK")
	check(platform.local_label.text == "player1 (you)" and avatar.sprite.modulate != platform.sprite.modulate, "DISTINGUISH_PLAYERS")
	remote.x = 56
	check(replica.apply_event(event(2,remote,"moved")) and platform.project(document,replica.view()), "REMOTE_MOVE")
	check(avatar.get_instance_id() == instance_id and avatar.position.x == platform.server_to_pixel(52) and avatar.target_x == platform.server_to_pixel(56), "STABLE_ID_NO_TELEPORT")
	var camera_x: float = platform.camera.position.x
	avatar._process(.02)
	check(avatar.position.x > platform.server_to_pixel(52) and avatar.position.x < avatar.target_x and avatar.sprite.texture == avatar.WALK_RIGHT, "REMOTE_INTERPOLATES")
	avatar._process(1)
	check(avatar.position.x == avatar.target_x and platform.camera.position.x == camera_x and replica.local_player().x == 50, "REMOTE_CANNOT_MOVE_CAMERA_OR_LOCAL_FACT")
	check(platform.project(document,replica.view(),51) and avatar.target_x == platform.server_to_pixel(56), "LOCAL_PREDICTION_DOES_NOT_AFFECT_REMOTE")
	avatar.position.x = -99999
	avatar.sprite.position.x = -99999
	avatar._process(0)
	check(avatar.position.x == avatar.target_x and avatar.sprite.position == Vector2.ZERO and replica.view().players.p2.x == 56, "REMOTE_TAMPER_NO_AUTHORITY_WRITE")
	var before := replica.snapshot()
	for i in range(1000): platform.project(document,replica.view(),51)
	check(platform.remote_players.size() == 1 and avatar.get_instance_id() == instance_id and replica.snapshot() == before, "NO_DUPLICATE_NODES_OR_FACT_WRITES")
	replica.begin_resync()
	platform.project(document,replica.view())
	check(platform.remote_players.p2 == avatar, "RESYNC_RETAINS_LAST_FACTS")
	check(replica.replace_snapshot(replica.snapshot()) and platform.project(document,replica.view()) and platform.remote_players.p2 == avatar, "HEALTHY_SNAPSHOT_RECONCILES_MEMBERSHIP")
	check(replica.apply_event(event(3,remote,"left")) and platform.project(document,replica.view()), "LEFT")
	check(platform.remote_players.is_empty() and avatar.get_parent() == null and avatar.is_queued_for_deletion(), "LEFT_REMOVES_IMMEDIATELY")
	remote.x = 20
	check(replica.apply_event(event(4,remote,"joined")) and platform.project(document,replica.view()), "REJOIN")
	check(platform.remote_players.p2.get_instance_id() != instance_id and platform.remote_players.p2.position.x == platform.server_to_pixel(20), "REJOIN_NEW_NODE_NO_OLD_TARGET")
	var bad := replica.view()
	bad.players.p2.x = 101
	check(not platform.project(document,bad) and platform.remote_players.p2.target_x == platform.server_to_pixel(20), "BAD_PROJECTION_ATOMIC")
	replica.invalidate("DISCONNECTED")
	platform.project(document,replica.view())
	check(platform.remote_players.size() == 1 and replica.view().status == "STALE", "STALE_IS_LAST_CONFIRMED_MEMBERSHIP")
	replica.clear()
	baseline.epoch = "e2"
	baseline.players = [local]
	check(replica.start(baseline,"p1","player1") and replica.install_map(document) and platform.project(document,replica.view()), "FRESH_BASELINE")
	check(platform.remote_players.is_empty(), "NEW_EPOCH_REMOVES_OLD_REMOTES")
	var scaled := document.duplicate(true)
	scaled.min_x = 100
	scaled.max_x = 300
	scaled.spawn_x = 200
	scaled.units_per_meter = 4
	scaled.erase("content_hash")
	scaled.content_hash = JSON.stringify(scaled,"",true).sha256_text()
	var population := {"p1":{"player_id":"p1","nickname":"player1","zone_id":"city/apartment","x":200}}
	for i in range(127):
		var id := "remote_%03d" % i
		population[id] = {"player_id":id,"nickname":id,"zone_id":"city/apartment","x":100 if i % 2 == 0 else 300}
	var full := {"epoch":"e3","map":{"map_id":scaled.map_id,"content_version":scaled.content_version,"content_hash":scaled.content_hash},"players":population,"local_player_id":"p1","confirmed_local_x":200}
	check(platform.project(scaled,full) and platform.remote_players.size() == 127, "PROTOCOL_POPULATION_CAP")
	check(platform.remote_players.remote_000.position.x == 32 and platform.remote_players.remote_001.position.x == 432, "SCALED_MAP_REMOTE_BOUNDARIES")
	var overflow := full.duplicate(true)
	overflow.players.extra = {"player_id":"extra","nickname":"extra","zone_id":"city/apartment","x":200}
	check(not platform.project(scaled,overflow) and platform.remote_players.size() == 127, "OVERSIZE_PROJECTION_NO_ALLOCATION")
	var boundary: Node2D = platform.remote_players.remote_001
	boundary.set_process(false)
	boundary.position.x = 99999
	boundary._process(1000)
	check(boundary.position.x == 432, "REMOTE_LARGE_DELTA_BOUND")
	full.players = {"p1":population.p1}
	check(platform.project(scaled,full) and platform.remote_players.is_empty(), "FULL_SNAPSHOT_REMOVAL")
	viewport.queue_free()
	await process_frame
	check(not is_instance_valid(avatar), "LEFT_NODE_FREED")
	print(JSON.stringify({"suite":"multiplayer","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
