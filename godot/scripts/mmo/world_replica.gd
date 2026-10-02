extends RefCounted
## Pure public-data reducer. Never holds sockets, scene nodes or renderer objects.

signal changed
signal local_moved(event: Dictionary, previous_x: int)

const Protocol = preload("res://scripts/mmo/protocol_v5.gd")
var _snapshot: Dictionary = {}
var _players: Dictionary = {}
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
		"map": _snapshot.get("map", {}).duplicate(true), "players": _players.duplicate(true),
		"local_player_id": _local_id, "confirmed_local_x": _players.get(_local_id, {}).get("x", null)}

func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func local_player() -> Dictionary:
	return _players.get(_local_id, {}).duplicate(true)

func clear() -> void:
	_snapshot = {}
	_players = {}
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
	if not _snapshot.is_empty() or not Protocol.token(local_id) or not Protocol.token(nickname):
		return _reject("INVALID_BASELINE")
	if not _valid_snapshot(value, local_id, nickname):
		return _reject("INVALID_BASELINE")
	_local_id = local_id
	_nickname = nickname
	_commit(value)
	return true

func install_map(value: Dictionary) -> bool:
	if _reconnect_required:
		return false
	if _snapshot.is_empty() or not Protocol.map_definition(value):
		return _reject("INVALID_MAP")
	var reference: Dictionary = _snapshot.map
	for key in ["map_id", "content_version", "content_hash"]:
		if value[key] != reference[key]:
			return _reject("MAP_MISMATCH")
	for player in _players.values():
		if not Protocol.integer(player.x, value.min_x, value.max_x):
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
	# All facts through this boundary precede state on the ordered TCP stream.
	if value.revision > _snapshot.revision:
		return _reject("SNAPSHOT_GAP")
	_commit(value)
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
	if value.revision <= _snapshot.revision:
		return _reject("DUPLICATE_EVENT")
	if value.revision != _snapshot.revision + 1:
		return _reject("REVISION_GAP")
	var players: Dictionary = _players.duplicate(true)
	var previous_local_x: int = _players.get(_local_id, {}).get("x", 0)
	var id: String = value.data.player_id if value.event == "left" else value.data.player.player_id
	if value.event == "joined":
		if players.has(id):
			return _reject("ALREADY_PRESENT")
		players[id] = value.data.player.duplicate(true)
	elif not players.has(id):
		return _reject("NOT_PRESENT")
	elif value.event == "left":
		if id == _local_id:
			return _reject("LOCAL_PLAYER_LEFT")
		players.erase(id)
	else:
		if players[id].nickname != value.data.player.nickname:
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
	if value.event == "moved" and id == _local_id:
		local_moved.emit(value.duplicate(true), previous_local_x)
	return true

func invalidate(reason: String) -> void:
	if not _snapshot.is_empty() and not _reconnect_required:
		_reject(reason)

func _valid_snapshot(value: Dictionary, local_id: String, nickname: String) -> bool:
	if not Protocol.snapshot(value):
		return false
	var local_found := false
	for player in value.players:
		if not _map.is_empty() and not Protocol.integer(player.x, _map.min_x, _map.max_x):
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
	_status = "STALE" if resync_pending else "SYNCED"
	_reason = "RESYNC_PENDING" if resync_pending else ""
	_reconnect_required = false
	changed.emit()

func _reject(reason: String) -> bool:
	_status = "STALE"
	_reason = reason
	_reconnect_required = true
	changed.emit()
	return false
