extends SceneTree

const Replica = preload("res://scripts/mmo/world_replica.gd")
const MAP := {"schema_version": 1, "map_id": "city/apartment", "content_version": 1,
	"min_x": 0, "max_x": 100, "spawn_x": 50, "units_per_meter": 1,
	"content_hash": "4f465435cbb8eb3e5154a4776be29e7aee4f73376e00fb26299bfbf0cfcd361b"}
var _checks := 0
var _failures: Array[String] = []

func player(id: String = "p1", name: String = "player1", x: int = 50) -> Dictionary:
	return {"player_id": id, "nickname": name, "zone_id": "city/apartment", "x": x}

func baseline(revision: int = 1, players: Array = []) -> Dictionary:
	return {"epoch": "e1", "revision": revision,
		"map": {"map_id": MAP.map_id, "content_version": MAP.content_version, "content_hash": MAP.content_hash},
		"players": [player()] if players.is_empty() else players.duplicate(true)}

func event(kind: String, revision: int, value: Dictionary) -> Dictionary:
	return {"protocol_version": 4, "type": "event", "event": kind, "epoch": "e1",
		"zone_id": "city/apartment", "revision": revision,
		"data": {"player_id": value.player_id} if kind == "left" else {"player": value.duplicate(true)}}

func ready_replica() -> RefCounted:
	var replica := Replica.new()
	check(replica.start(baseline(), "p1", "player1") and replica.install_map(MAP), "baseline and map")
	return replica

func _initialize() -> void:
	var replica := ready_replica()
	check(replica.view().status == "SYNCED" and replica.view().confirmed_local_x == 50, "confirmed local X")
	var input := event("joined", 2, player("p2", "player2"))
	check(replica.apply_event(input) and replica.view().players.size() == 2, "joined N+1")
	input.data.player.x = 99
	check(replica.view().players.p2.x == 50, "event input copied")
	check(replica.apply_event(event("moved", 3, player("p1", "player1", 51))), "own moved")
	check(replica.view().confirmed_local_x == 51, "own authoritative X")
	check(replica.apply_event(event("moved", 4, player("p2", "player2", 52))), "remote moved")
	check(replica.view().confirmed_local_x == 51 and replica.view().players.p2.x == 52, "remote move preserves local X")
	check(replica.apply_event(event("left", 5, player("p2", "player2"))) and replica.view().players.size() == 1, "left")
	var exposed: Dictionary = replica.view()
	exposed.players.p1.x = 80
	exposed.map.map_id = "city/street"
	var exposed_snapshot: Dictionary = replica.snapshot()
	exposed_snapshot.players[0].x = 81
	var exposed_local: Dictionary = replica.local_player()
	exposed_local.x = 82
	check(replica.view().confirmed_local_x == 51 and replica.view().map.map_id == "city/apartment", "defensive output copies")
	check(replica.begin_resync() and replica.view().status == "STALE" and not replica.view().reconnect_required, "ordinary state resync pending")
	check(replica.apply_event(event("joined", 6, player("p2", "player2"))), "events while awaiting state")
	check(replica.view().status == "STALE" and replica.view().revision == 6, "pending resync stays stale")
	var replacement := baseline(6, [player("p1", "player1", 51), player("p2", "player2")])
	check(replica.replace_snapshot(replacement) and replica.view().status == "SYNCED", "state snapshot replaces whole baseline")
	replacement.players[0].x = 83
	check(replica.view().confirmed_local_x == 51, "snapshot input copied")
	check(replica.apply_event(event("left", 7, player("p2", "player2"))), "post-resync N+1")
	check(replica.view().revision == 7, "no double application at snapshot boundary")

	for kind in ["duplicate", "gap", "epoch", "zone", "already_joined", "unknown_move", "unknown_left", "identity", "duplicate_name", "outside_map", "local_left", "invalid_schema"]:
		replica = ready_replica()
		var bad := event("moved", 2, player("p1", "player1", 51))
		match kind:
			"duplicate": bad.revision = 1
			"gap": bad.revision = 3
			"epoch": bad.epoch = "e2"
			"zone":
				bad.zone_id = "city/street"
				bad.data.player.zone_id = "city/street"
			"already_joined": bad.event = "joined"
			"unknown_move": bad.data.player = player("p2", "player2")
			"unknown_left": bad = event("left", 2, player("p2", "player2"))
			"identity": bad.data.player.nickname = "player2"
			"duplicate_name": bad = event("joined", 2, player("p2", "player1"))
			"outside_map": bad.data.player.x = 101
			"local_left": bad = event("left", 2, player())
			"invalid_schema": bad.extra = true
		var before: Dictionary = replica.snapshot()
		check(not replica.apply_event(bad), kind + " rejected")
		check(replica.snapshot() == before and replica.view().status == "STALE" and replica.view().resync_required and replica.view().reconnect_required, kind + " atomic stale")
		check(not replica.apply_event(event("moved", 2, player("p1", "player1", 53))) and replica.snapshot() == before, kind + " terminal stream")
		check(not replica.replace_snapshot(baseline(3)), kind + " state cannot repair corrupt stream")
		check(not replica.install_map(MAP), kind + " map cannot repair corrupt stream")

	for kind in ["rollback", "gap", "epoch", "map", "missing_local", "identity", "outside_remote"]:
		replica = ready_replica()
		var bad := baseline()
		match kind:
			"rollback": bad.revision = 0
			"gap": bad.revision = 2
			"epoch": bad.epoch = "e2"
			"map": bad.map.content_version = 2
			"missing_local": bad.players = [player("p2", "player2")]
			"identity": bad.players[0].nickname = "player2"
			"outside_remote": bad.players.append(player("p2", "player2", 101))
		check(not replica.replace_snapshot(bad) and replica.view().confirmed_local_x == 50, "snapshot " + kind + " rejected atomically")
		if kind == "gap":
			check(replica.view().stale_reason == "SNAPSHOT_GAP" and replica.view().reconnect_required and replica.view().revision == 1, "snapshot cannot hide missing events")

	replica = Replica.new()
	var before_map := baseline(1, [player(), player("p2", "player2", 101)])
	check(replica.start(before_map, "p1", "player1") and not replica.install_map(MAP), "all player bounds checked when map arrives")
	replica.clear()
	check(replica.view().status == "EMPTY" and replica.view().confirmed_local_x == null and replica.snapshot().is_empty(), "clear old sequence")
	var new_epoch := baseline()
	new_epoch.epoch = "e2"
	check(replica.start(new_epoch, "p1", "player1") and replica.view().epoch == "e2", "fresh enter accepts new epoch")
	check(not replica.apply_event(event("moved", 2, player("p1", "player1", 51))), "old epoch event cannot update new enter")
	replica = ready_replica()
	replica.invalidate("DISCONNECTED")
	check(replica.view().status == "STALE" and replica.view().confirmed_local_x == 50 and replica.view().reconnect_required, "disconnect retains only stale facts")
	var crowded: Array = []
	for index in range(128):
		crowded.append(player("p%03d" % index, "name%d" % index))
	replica = Replica.new()
	check(replica.start(baseline(1, crowded), "p000", "name0"), "wire population cap baseline")
	check(not replica.apply_event(event("joined", 2, player("p999", "name999"))), "population cap enforced after joined")
	print(JSON.stringify({"suite": "replica", "checks": _checks, "failures": _failures, "result": "PASS" if _failures.is_empty() else "FAIL"}))
	quit(0 if _failures.is_empty() else 1)

func check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)
