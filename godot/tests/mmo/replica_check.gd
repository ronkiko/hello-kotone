extends SceneTree
const Protocol = preload("res://scripts/mmo/protocol_v8.gd")
const Replica = preload("res://scripts/mmo/world_replica.gd")
const MAP := {"schema_version":1,"map_id":"city/apartment","content_version":1,"min_x":0,"max_x":100,"spawn_x":50,"units_per_meter":1,"content_hash":"4f465435cbb8eb3e5154a4776be29e7aee4f73376e00fb26299bfbf0cfcd361b"}
var checks := 0
var failures := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
static func player(id: String = "p1", name: String = "player1", position_mm: int = 50000) -> Dictionary:
	return {"player_id":id,"nickname":name,"zone_id":"city/apartment","motion":{"position_mm":position_mm,"velocity_mm_s":0,"facing":1,"last_applied_control_seq":0,"simulation_tick":0},"contacts":[],"character":{"game_card_id":"hello-kotone","realm_id":"local","character_id":id,"display_name":name,"appearance_schema_version":2,"appearance_payload":{"character_model_id":"kotone","body_variant_id":"standard","face_style_id":"soft","hair_style_id":"short","hair_color_id":"chestnut"}}}
func baseline() -> Dictionary:
	return {"epoch":"e1","revision":1,"map":{"map_id":MAP.map_id,"content_version":1,"content_hash":MAP.content_hash},"players":[player()]}
func ready_replica() -> RefCounted:
	var replica := Replica.new()
	check(replica.world_session.bind({"identity":{"game_card_id":"hello-kotone","realm_id":"local","realm_instance_id":"e1"},"capabilities":["control_set","logout","map","state","world_rules"]}), "realm bound")
	check(replica.start(baseline(), "p1", "player1") and replica.install_map(MAP), "current baseline")
	return replica
func sample(seq: int = 1, revision: int = 5) -> Dictionary:
	var p := player()
	p.motion.facing = -1
	p.motion.simulation_tick = 4
	p.motion.last_applied_control_seq = 1
	return {"protocol_version":8,"type":"event","event":"motion_frame","epoch":"e1","zone_id":MAP.map_id,"revision":revision,"data":{"realm_instance_id":"e1","zone_package_id":MAP.map_id,"zone_generation":1,"frame_seq":seq,"players":[p]}}
func _initialize() -> void:
	var replica := ready_replica()
	check(replica.apply_event(sample()), "coalesced physics revisions accepted")
	check(replica.local_player().motion.facing == -1 and replica.local_player().motion.position_mm == 50000, "stationary facing sample")
	check(replica.apply_event(sample(3,8)), "coalesced publication sequence accepted")
	check(not replica.apply_event(sample(3,8)) and replica.view().reconnect_required, "duplicate fenced")
	for field in ["realm_instance_id","zone_package_id","zone_generation","frame_seq"]:
		replica = ready_replica()
		var bad := sample()
		bad.data[field] = "other" if field in ["realm_instance_id","zone_package_id"] else 0
		check(not replica.apply_event(bad) and replica.view().reconnect_required, "invalid scope " + field)
	for field in ["character","nickname","player_id"]:
		replica = ready_replica()
		var bad := sample()
		if field == "character": bad.data.players[0].character.appearance_payload.hair_color_id = "copper"
		else: bad.data.players[0][field] = "other"
		check(not replica.apply_event(bad), "identity fence " + field)
	replica = ready_replica()
	var newer := baseline()
	newer.revision = 9
	newer.players[0].motion.simulation_tick = 8
	check(replica.replace_snapshot(newer), "reliable full snapshot may skip unpublished physics")
	check(not replica.replace_snapshot(baseline()), "snapshot rollback fenced")
	replica = ready_replica()
	var joined := {"protocol_version":8,"type":"event","event":"joined","epoch":"e1","zone_id":MAP.map_id,"revision":6,"data":{"player":player("p2","Bob",50400)}}
	check(replica.apply_event(joined) and replica.view().players.size() == 2, "reliable join through physics gap")
	var left := {"protocol_version":8,"type":"event","event":"left","epoch":"e1","zone_id":MAP.map_id,"revision":9,"data":{"player_id":"p2"}}
	check(replica.apply_event(left) and replica.view().players.size() == 1, "reliable leave")
	var before: Dictionary = replica.snapshot()
	before.players.clear()
	check(replica.view().players.size() == 1, "defensive values")
	print(JSON.stringify({"suite":"motion-replica","checks":checks,"failures":failures,"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
