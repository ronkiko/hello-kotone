extends RefCounted
## Pure public-data reducer. Never holds sockets, scene nodes or renderer objects.

signal changed
signal motion_received(event: Dictionary)
signal authoritative_snapshot_received(snapshot: Dictionary)
var _frame_seq := 0
var _zone_generation := 1
var _simulation_tick := -1

const Protocol = preload("res://scripts/mmo/protocol_v8.gd")
const WorldSession = preload("res://scripts/mmo/world_session.gd")
var world_session := WorldSession.new()
var _snapshot: Dictionary = {}
var _players: Dictionary = {}
var _latest_frame_samples: Dictionary = {}
var _map: Dictionary = {}
var _local_id := ""
var _nickname := ""
var _status := "EMPTY"
var _reason := ""
var _reconnect_required := false

func view() -> Dictionary:
	return {"status": _status, "stale_reason": _reason,
		"resync_required": _status == "STALE", "reconnect_required": _reconnect_required,
		"epoch": _snapshot.get("epoch", ""), "revision": _snapshot.get("revision", 0),
		"zone_generation": _zone_generation,
		"map": _snapshot.get("map", {}).duplicate(true), "players": _players.duplicate(true),
		"local_player_id": _local_id, "confirmed_local_position_mm": _players.get(_local_id, {}).get("motion", {}).get("position_mm", null)}

func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func local_player() -> Dictionary:
	return _players.get(_local_id, {}).duplicate(true)

func latest_frame_sample(player_id: String) -> Dictionary:
	return _latest_frame_samples.get(player_id, {}).duplicate(true)

func clear() -> void:
	_frame_seq = 0
	_zone_generation = 1
	_simulation_tick = -1
	world_session.clear()
	_snapshot = {}
	_players = {}
	_latest_frame_samples = {}
	_map = {}
	_local_id = ""
	_nickname = ""
	_status = "EMPTY"
	_reason = ""
	_reconnect_required = false
	changed.emit()

func start(value: Dictionary, local_id: String, nickname: String) -> bool:
	# A new enter/session is the only operation that can establish a new epoch.
	if _reconnect_required:
		return false
	if not world_session.accepts_epoch(value.get("epoch", "")):
		return _reject("WRONG_REALM_INSTANCE")
	if not _snapshot.is_empty() or not Protocol.token(local_id) or not Protocol.display_name(nickname):
		return _reject("INVALID_BASELINE")
	if not _valid_snapshot(value, local_id, nickname):
		return _reject("INVALID_BASELINE")
	_latest_frame_samples.clear()
	_local_id = local_id
	_nickname = nickname
	_commit(value)
	return true

func install_map(value: Dictionary) -> bool:
	if _reconnect_required:
		return false
	if not world_session.view().active:
		return _reject("UNBOUND_REALM")
	if _snapshot.is_empty() or not Protocol.map_definition(value):
		return _reject("INVALID_MAP")
	var reference: Dictionary = _snapshot.map
	for key in ["map_id", "content_version", "content_hash"]:
		if value[key] != reference[key]:
			return _reject("MAP_MISMATCH")
	for player in _players.values():
		if not _inside_map(player, value):
			return _reject("OUTSIDE_MAP")
	_map = value.duplicate(true)
	return true

func begin_resync() -> bool:
	if _snapshot.is_empty() or _reconnect_required:
		return false
	_status = "STALE"
	_reason = "RESYNC_PENDING"
	changed.emit()
	return true

func replace_snapshot(value: Dictionary) -> bool:
	if _snapshot.is_empty() or _reconnect_required:
		return false
	if not _valid_snapshot(value, _local_id, _nickname):
		return _reject("INVALID_SNAPSHOT")
	if value.epoch != _snapshot.epoch:
		return _reject("WRONG_EPOCH")
	if value.map != _snapshot.map:
		return _reject("MAP_MISMATCH")
	if value.revision < _snapshot.revision:
		return _reject("SNAPSHOT_ROLLBACK")
	var applied_control_seq := -1
	for player in value.players:
		if _players.has(player.player_id) and player.physics != _players[player.player_id].physics:
			return _reject("PHYSICS_BINDING_CHANGED")
		if player.player_id == _local_id:
			applied_control_seq = player.motion.last_applied_control_seq
	if applied_control_seq < _players[_local_id].motion.last_applied_control_seq:
		return _reject("SNAPSHOT_CONTROL_SEQUENCE_ROLLBACK")
	if _snapshot_tick(value) < _simulation_tick:
		return _reject("SNAPSHOT_TICK_ROLLBACK")
	# All facts through this boundary precede state on the ordered TCP stream.

	_latest_frame_samples.clear()
	_commit(value)
	authoritative_snapshot_received.emit(value.duplicate(true))
	return true

func apply_event(value: Dictionary) -> bool:
	if _snapshot.is_empty() or _reconnect_required:
		return _reject("NO_VALID_STREAM") if not _reconnect_required else false
	if not Protocol.event(value):
		return _reject("INVALID_EVENT")
	if value.epoch != _snapshot.epoch:
		return _reject("WRONG_EPOCH")
	if value.zone_id != _snapshot.map.map_id:
		return _reject("WRONG_ZONE")
	if value.event == "motion_frame":
		if value.data.zone_generation != _zone_generation or value.data.frame_seq <= _frame_seq or value.revision < _snapshot.revision \
			or value.data.simulation_tick < _simulation_tick:
			return _reject("STALE_MOTION_FRAME")
		var incoming := {}
		for sample in value.data.players:
			if not _players.has(sample.player_id) or incoming.has(sample.player_id):
				return _reject("MOTION_MEMBERSHIP_CHANGED")
			if sample.player_id == _local_id and sample.last_applied_control_seq < _players[_local_id].motion.last_applied_control_seq:
				return _reject("STALE_CONTROL_SEQUENCE")
			incoming[sample.player_id] = sample
		if incoming.size() != _players.size(): return _reject("MOTION_MEMBERSHIP_CHANGED")
		var next: Dictionary = _snapshot.duplicate(true)
		next.players = []
		var ids := _players.keys()
		ids.sort()
		for id in ids:
			var player: Dictionary = _players[id].duplicate(true)
			var sample: Dictionary = incoming[id]
			var motion: Dictionary = player.motion.duplicate(true)
			motion.position_mm = sample.position_mm
			motion.velocity_mm_s = sample.velocity_mm_s
			motion.facing = sample.facing
			motion.last_applied_control_seq = sample.last_applied_control_seq
			motion.control_started_tick = sample.control_started_tick
			motion.simulation_tick = value.data.simulation_tick
			player.motion = motion
			player.contacts = sample.contacts.duplicate()
			next.players.append(player)
		next.revision = value.revision
		if not _valid_snapshot(next, _local_id, _nickname): return _reject("INVALID_MOTION")
		_latest_frame_samples = incoming.duplicate(true)
		_frame_seq = value.data.frame_seq
		_commit(next, _status == "STALE")
		motion_received.emit(value.duplicate(true))
		return true
	if value.revision <= _snapshot.revision: return _reject("STALE_LIFECYCLE")
	var players: Dictionary = _players.duplicate(true)
	var id: String = value.data.player_id if value.event == "left" else value.data.player.player_id
	if value.event == "joined":
		_latest_frame_samples.clear()
		if players.has(id):
			return _reject("ALREADY_PRESENT")
		players[id] = value.data.player.duplicate(true)
	elif not players.has(id):
		return _reject("NOT_PRESENT")
	elif value.event == "left":
		_latest_frame_samples.clear()
		if id == _local_id:
			return _reject("LOCAL_PLAYER_LEFT")
		players.erase(id)
	else:
		if players[id].nickname != value.data.player.nickname or players[id].get("character") != value.data.player.get("character"):
			return _reject("IDENTITY_CHANGED")
		players[id] = value.data.player.duplicate(true)
	var next: Dictionary = _snapshot.duplicate(true)
	next.revision = value.revision
	next.players = []
	var ids := players.keys()
	ids.sort()
	for key in ids:
		next.players.append(players[key])
	if not _valid_snapshot(next, _local_id, _nickname):
		return _reject("INVALID_MEMBERSHIP")
	# Continue processing preceding events during state resync, but remain stale
	# until the correlated snapshot arrives. Nothing is buffered/replayed.
	var resync_pending := _status == "STALE"
	_commit(next, resync_pending)
	return true

func invalidate(reason: String) -> void:
	if not _snapshot.is_empty() and not _reconnect_required:
		_reject(reason)

func _valid_snapshot(value: Dictionary, local_id: String, nickname: String) -> bool:
	if not Protocol.snapshot(value):
		return false
	var local_found := false
	for player in value.players:
		if not _map.is_empty() and not _inside_map(player, _map):
			return false
		if player.player_id == local_id:
			if player.nickname != nickname:
				return false
			local_found = true
	return local_found

func _commit(value: Dictionary, resync_pending: bool = false) -> void:
	_snapshot = value.duplicate(true)
	_players = {}
	for player in _snapshot.players:
		_players[player.player_id] = player.duplicate(true)
		_simulation_tick = maxi(_simulation_tick, player.motion.simulation_tick)
	_status = "STALE" if resync_pending else "SYNCED"
	_reason = "RESYNC_PENDING" if resync_pending else ""
	_reconnect_required = false
	changed.emit()

func _reject(reason: String) -> bool:
	world_session.invalidate()
	_status = "STALE"
	_reason = reason
	_reconnect_required = true
	changed.emit()
	return false

func _inside_map(player: Dictionary, document: Dictionary) -> bool:
	var position: int = player.motion.position_mm
	return float(position) >= float(document.min_x) * 1000.0 / float(document.units_per_meter) \
		and float(position) <= float(document.max_x) * 1000.0 / float(document.units_per_meter)

func _snapshot_tick(value: Dictionary) -> int:
	var latest := -1
	for player in value.players:
		latest = maxi(latest, player.motion.simulation_tick)
	return latest
