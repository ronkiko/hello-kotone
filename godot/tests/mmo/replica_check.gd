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
	return {"player_id":id,"nickname":name,"zone_id":"city/apartment","motion":{"position_mm":position_mm,"velocity_mm_s":0,"facing":1,"last_applied_control_seq":0,"control_started_tick":0,"simulation_tick":0},"contacts":[],"physics":binding(),"character":{"game_card_id":"hello-kotone","realm_id":"local","character_id":id,"display_name":name,"appearance_schema_version":2,"appearance_payload":{"character_model_id":"kotone","body_variant_id":"standard","face_style_id":"soft","hair_style_id":"short","hair_color_id":"chestnut"}}}
func baseline() -> Dictionary:
	return {"epoch":"e1","revision":1,"map":{"map_id":MAP.map_id,"content_version":1,"content_hash":MAP.content_hash},"players":[player()]}
func ready_replica() -> RefCounted:
	var replica := Replica.new()
	check(replica.world_session.bind({"identity":{"game_card_id":"hello-kotone","realm_id":"local","realm_instance_id":"e1"},"capabilities":["control_set","logout","map","state","world_rules"]}), "realm bound")
	check(replica.start(baseline(), "p1", "player1") and replica.install_map(MAP), "current baseline")
	return replica
func sample(seq: int = 1, revision: int = 5, response_delta: int = 0) -> Dictionary:
	var p := player()
	var contact_response_contacts: Array = ["p2"] if response_delta != 0 else []
	var contact_impact_sources: Array = ["p2"] if response_delta != 0 else []
	return {"protocol_version":8,"type":"event","event":"motion_frame","epoch":"e1","zone_id":MAP.map_id,"revision":revision,"data":{"realm_instance_id":"e1","zone_package_id":MAP.map_id,"zone_generation":1,"frame_seq":seq,"simulation_tick":4,"players":[{"player_id":p.player_id,"position_mm":p.motion.position_mm,"velocity_mm_s":0,"facing":-1,"last_applied_control_seq":1,"control_started_tick":0,"contacts":[],"contact_delta_velocity_mm_s":response_delta,"contact_response_facing":-1 if response_delta != 0 else 0,"contact_response_tick":3 if response_delta != 0 else 0,"contact_response_contacts":contact_response_contacts,"contact_impact_sources":contact_impact_sources}]}}
func _initialize() -> void:
	var replica := ready_replica()
	check(replica.apply_event(sample()), "coalesced physics revisions accepted")
	check(replica.local_player().motion.facing == -1 and replica.local_player().motion.position_mm == 50000 \
		and replica.local_player().nickname == "player1" and replica.local_player().character.character_id == "p1", "physics sample merges over static identity")
	check(replica.latest_frame_sample("p1").contact_delta_velocity_mm_s == 0, "transient frame sample is available to presentation")
	check(replica.apply_event(sample(3,8)), "coalesced publication sequence accepted")
	check(not replica.apply_event(sample(3,8)) and replica.view().reconnect_required, "duplicate fenced")
	for field in ["realm_instance_id","zone_package_id","zone_generation","frame_seq","simulation_tick"]:
		replica = ready_replica()
		var bad := sample()
		bad.data[field] = "other" if field in ["realm_instance_id","zone_package_id"] else (-1 if field == "simulation_tick" else 0)
		check(not replica.apply_event(bad) and replica.view().reconnect_required, "invalid scope " + field)
	for field in ["character","nickname","zone_id","player_id"]:
		replica = ready_replica()
		var bad := sample()
		bad.data.players[0][field] = "other"
		check(not replica.apply_event(bad), "static identity rejected in motion sample " + field)
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

static func physics(model: String = "kotone") -> Dictionary:
	return {"character_model_id":model,"physics_profile_revision":"hello_kotone_physics_v4",
		"body":{"body_profile_id":model+"_body_v2","mass_g":70000 if model=="kotone" else 50000,
		"collision_width_mm":400 if model=="kotone" else 360,
		"collision_height_mm":1720 if model=="kotone" else 1550},
		"motor":{"motor_profile_id":model+"_motor_v3","drive_force_mN":560000,"brake_force_mN":560000,
		"top_speed_mm_s":1300 if model=="kotone" else 1820}}

static func binding(model: String = "kotone") -> Dictionary:
	return {"physics_profile_revision":"hello_kotone_physics_v4", "body_profile_id":model+"_body_v2", "motor_profile_id":model+"_motor_v3"}

static func rules() -> Dictionary:
	return {"physics_hz":60,"publication_hz":20,"control_interval_ms":50,"engage_ms":100,
		"physics_profiles":[physics("kotone"),physics("yuna")]}
