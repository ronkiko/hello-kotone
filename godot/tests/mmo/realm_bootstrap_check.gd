extends SceneTree
## v7 selected-character realm-before-zone boundary, adversarial content and restart checks.
const Protocol = preload("res://scripts/mmo/protocol_v8.gd")
const Replica = preload("res://scripts/mmo/world_replica.gd")
const Fixtures = preload("res://tests/mmo/replica_check.gd")
var checks := 0
var failures: Array[String] = []
var client: Node

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func identity(epoch: String = "e1") -> Dictionary:
	return {"game_card_id": "hello-kotone", "realm_id": "local", "realm_instance_id": epoch}

func bootstrap(epoch: String = "e1") -> Dictionary:
	return {"identity": identity(epoch), "capabilities": ["control_set", "logout", "map", "state", "world_rules"]}

func character() -> Dictionary:
	return {"game_card_id": "hello-kotone", "realm_id": "local", "character_id": "p1", "display_name": "player1", "appearance_schema_version": 2,
		"appearance_payload": {"character_model_id": "kotone", "body_variant_id": "standard", "face_style_id": "soft", "hair_style_id": "short", "hair_color_id": "chestnut"}}

func baseline(epoch: String = "e1") -> Dictionary:
	return {"epoch": epoch, "revision": 1,
		"map": {"map_id": Fixtures.MAP.map_id, "content_version": Fixtures.MAP.content_version, "content_hash": Fixtures.MAP.content_hash},
		"players": [Fixtures.player()]}

func entry(epoch: String = "e1") -> Dictionary:
	return {"session_id": "s1", "player_id": "p1", "bootstrap": bootstrap(epoch), "snapshot": baseline(epoch)}

func reply(op: String, data: Dictionary) -> Dictionary:
	return {"protocol_version": 8, "type": "response", "request_id": "r1", "op": op, "status": "ok", "data": data, "error": null}

func deliver(op: String, data: Dictionary) -> void:
	client._pending = {"op": op, "request_id": "r1", "payload": {}}
	client._on_frame(JSON.stringify(reply(op, data)).to_utf8_buffer())

func reset() -> void:
	client._clear_session()
	client._nickname = "player1"
	client._expected_identity = identity()
	client._expected_character = character()
	client.state = "ENTERING_WORLD"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	client = root.get_node("MmoClient")
	# Observe the first reducer commit: realm binding must already exist then.
	var committed: Array = []
	client.world_replica.changed.connect(func():
		if not client.world_replica.snapshot().is_empty() and client.world_replica.view().status == "SYNCED":
			committed.append(client.world_session.view()))
	var replica := Replica.new()
	check(not replica.start(baseline(), "p1", "player1") and replica.snapshot().is_empty(), "UNBOUND_ZONE_REJECTED")
	for bad in [{}, {"identity": identity(), "capabilities": ["control_set", "control_set"]}, {"identity": identity(), "capabilities": [true]}, {"identity": identity(), "capabilities": ["x".repeat(129)]}, {"identity": identity(), "capabilities": ["future\n"]}, {"identity": {"game_card_id": "hello-kotone", "realm_id": "local\n", "realm_instance_id": "e1"}, "capabilities": []}, {"identity": identity(), "capabilities": ["control_set"], "session_rules": {}}]:
		check(not Protocol.bootstrap(bad), "STRICT_BOOTSTRAP")
	check(Protocol.bootstrap({"identity": identity(), "capabilities": []}), "GENERIC_EMPTY_CAPABILITIES")
	check(Protocol.response(reply("enter", entry())), "VALID_V8_ENTER")
	var old_version := reply("enter", entry())
	old_version.protocol_version = 5
	check(not Protocol.response(old_version), "V5_BREAKING_SHAPE_REJECTED")
	for mode in ["missing", "instance", "card", "capability", "host_policy"]:
		reset()
		var bad := entry()
		match mode:
			"missing": bad.erase("bootstrap")
			"instance": bad.bootstrap.identity.realm_instance_id = "e2"
			"card": bad.bootstrap.identity.game_card_id = "test-minimal"
			"capability": bad.bootstrap.capabilities.erase("control_set")
			"host_policy": bad.bootstrap.idle_timeout_ms = 600
		deliver("enter", bad)
		check(client.state == "FAILED" and client.world_replica.snapshot().is_empty() and committed.is_empty(), "NO_ZONE_BEFORE_VALID_BIND_" + mode)
		check(client.last_error.outcome_unknown and not client.world_session.view().active, "FAILED_ENTER_FENCES_" + mode)
	reset()
	deliver("enter", entry())
	check(not committed.is_empty() and committed[-1].identity == identity() and committed[-1].active, "REALM_BOUND_BEFORE_ZONE_COMMIT")
	check(client.world_session.view().capabilities == bootstrap().capabilities, "WORLD_CAPABILITIES_RETAINED")
	var exposed: Dictionary = client.world_session.view()
	exposed.identity.realm_id = "mutated"
	exposed.capabilities.clear()
	check(client.world_session.view().identity == identity() and client.world_session.supports("control_set"), "DETACHED_REALM_VALUES")
	for op in ["map", "world_rules"]:
		for field in ["game_card_id", "realm_id", "realm_instance_id"]:
			reset()
			deliver("enter", entry())
			var before: Dictionary = client.world_replica.snapshot()
			var scope := identity()
			scope[field] = "different"
			var data := {"identity": scope, "map": Fixtures.MAP} if op == "map" else {"identity": scope, "movement": Fixtures.rules()}
			deliver(op, data)
			check(client.state == "FAILED" and client.last_error.code == "REALM_IDENTITY_MISMATCH", "SCOPED_REPLY_REJECTED_" + op + "_" + field)
			check(client.world_replica.snapshot() == before and client.map_document.is_empty() and client.world_rules.is_empty(), "NO_FOREIGN_PRESENTATION_" + op + "_" + field)
			check(not client.world_session.view().active, "FOREIGN_REPLY_FENCES_REALM")
	# Same content bytes may be reused only after fresh binding. An old network map cannot.
	reset()
	client._expected_identity = identity("e2")
	deliver("enter", entry("e2"))
	check(client.world_session.view().identity == identity("e2") and client.world_replica.view().epoch == "e2", "FRESH_INSTANCE_BINDS")
	check(client.world_replica.install_map(Fixtures.MAP), "VERIFIED_CONTENT_REUSED_IN_NEW_INSTANCE")
	deliver("map", {"identity": identity(), "map": Fixtures.MAP})
	check(client.state == "FAILED" and client.last_error.code == "REALM_IDENTITY_MISMATCH", "OLD_MAP_SAME_BYTES_REJECTED")
	reset()
	client._expected_identity = identity("e2")
	deliver("enter", entry("e2"))
	client._on_frame(JSON.stringify({"protocol_version": 8, "type": "event", "event": "joined", "epoch": "e1", "zone_id": "city/apartment", "revision": 2, "data": {"player": Fixtures.player("p2", "Bob", 50400)}}).to_utf8_buffer())
	check(client.state == "FAILED" and client.world_replica.view().confirmed_local_position_mm == 50000 and client.world_replica.view().stale_reason == "WRONG_EPOCH", "OLD_FACT_REJECTED_BEFORE_PROJECTION")
	reset()
	client._expected_identity = identity("e2")
	deliver("enter", entry("e2"))
	deliver("state", {"snapshot": baseline("e1")})
	check(client.state == "FAILED" and client.world_replica.view().confirmed_local_position_mm == 50000, "OLD_STATE_REJECTED")
	client.disconnect_world()
	check(client.world_session.view().identity.is_empty() and client.world_replica.snapshot().is_empty(), "TEARDOWN_CLEARS_REALM_AND_ZONE")
	print(JSON.stringify({"suite": "recovery", "checks": checks, "failures": failures, "result": "PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
