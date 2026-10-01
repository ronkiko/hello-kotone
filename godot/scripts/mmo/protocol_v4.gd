extends RefCounted
## Public wire validation only. Replica reduction and presentation belong elsewhere.

const VERSION := 4
const MAX_FRAME_BYTES := 65536
const WireJson = preload("res://scripts/mmo/wire_json.gd")

static func decode(frame: PackedByteArray) -> Dictionary:
	if frame.is_empty() or frame.size() + 1 > MAX_FRAME_BYTES or frame[-1] == 13:
		return {}
	return WireJson.new().decode(frame)

static func fields(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

static func integer(value: Variant, low: int = 0, high: int = 9007199254740991) -> bool:
	return value is int and value >= low and value <= high

static func matches(value: Variant, pattern: String) -> bool:
	return value is String and RegEx.create_from_string(pattern).search(value) != null

static func token(value: Variant) -> bool:
	return matches(value, "^[A-Za-z0-9_-]{1,64}$")

static func digest(value: Variant) -> bool:
	return matches(value, "^[0-9a-f]{64}$")

static func zone(value: Variant) -> bool:
	return value is String and value.length() <= 128 and matches(value, "^[a-z][a-z0-9_-]*(/[a-z][a-z0-9_-]*)*$")

static func endpoint(value: Variant) -> bool:
	return fields(value, ["server_id", "host", "port"]) and token(value.server_id) \
		and matches(value.host, "^[A-Za-z0-9.:-]{1,253}$") and integer(value.port, 1, 65535)

static func player(value: Variant) -> bool:
	return fields(value, ["player_id", "nickname", "zone_id", "x"]) and token(value.player_id) \
		and token(value.nickname) and zone(value.zone_id) and integer(value.x)

static func map_reference(value: Variant) -> bool:
	return fields(value, ["map_id", "content_version", "content_hash"]) and zone(value.map_id) \
		and integer(value.content_version, 1) and digest(value.content_hash)

static func snapshot(value: Variant) -> bool:
	if not fields(value, ["epoch", "revision", "map", "players"]) or not token(value.epoch) \
		or not integer(value.revision) or not map_reference(value.map) or not value.players is Array \
		or value.players.is_empty() or value.players.size() > 128:
		return false
	var last_id := ""
	var names: Dictionary = {}
	for item in value.players:
		if not player(item) or item.zone_id != value.map.map_id or item.player_id <= last_id or names.has(item.nickname):
			return false
		last_id = item.player_id
		names[item.nickname] = true
	return true

static func map_definition(value: Variant) -> bool:
	if not fields(value, ["schema_version", "map_id", "content_version", "content_hash", "min_x", "max_x", "spawn_x", "units_per_meter"]):
		return false
	if not integer(value.schema_version, 1, 1) or not zone(value.map_id) or not integer(value.content_version, 1) \
		or not digest(value.content_hash) or not integer(value.min_x) or not integer(value.max_x, 1) \
		or value.min_x >= value.max_x or not integer(value.spawn_x, value.min_x, value.max_x) \
		or not integer(value.units_per_meter, 1, 1000000):
		return false
	# Schema 1 is ASCII + integers, so Godot's sorted compact JSON is canonical.
	var canonical: Dictionary = value.duplicate()
	canonical.erase("content_hash")
	return JSON.stringify(canonical, "", true).sha256_text() == value.content_hash

static func response(value: Variant) -> bool:
	if not fields(value, ["protocol_version", "type", "request_id", "op", "status", "data", "error"]) \
		or not integer(value.protocol_version, VERSION, VERSION) or value.type != "response":
		return false
	if value.status in ["rejected", "error"]:
		return value.data == null and fields(value.error, ["code", "message"]) \
			and matches(value.error.code, "^[A-Z_]{1,64}$") and value.error.message is String \
			and value.error.message.length() >= 1 and value.error.message.length() <= 256 \
			and not RegEx.create_from_string("[\\x00-\\x1f\\x7f]").search(value.error.message) \
			and ((token(value.request_id) and value.op in ["login", "enter", "map", "state", "logout"]) \
				or (value.status == "error" and value.request_id == null and value.op == null))
	if value.status != "ok" or value.error != null or not token(value.request_id):
		return false
	var data: Variant = value.data
	match value.op:
		"login":
			return fields(data, ["ticket", "expires_in_ms", "game_server"]) and digest(data.ticket) \
				and integer(data.expires_in_ms, 1, 30000) and endpoint(data.game_server)
		"enter":
			if not fields(data, ["session_id", "player_id", "snapshot"]) or not token(data.session_id) \
				or not token(data.player_id) or not snapshot(data.snapshot):
				return false
			for item in data.snapshot.players:
				if item.player_id == data.player_id:
					return true
			return false
		"map":
			return fields(data, ["map"]) and map_definition(data.map)
		"state":
			return fields(data, ["snapshot"]) and snapshot(data.snapshot)
		"logout":
			return fields(data, ["flush"]) and fields(data.flush, ["status", "save_version"]) \
				and ((data.flush.status == "completed" and integer(data.flush.save_version)) \
					or (data.flush.status == "disabled" and data.flush.save_version == null))
	return false

static func event(value: Variant) -> bool:
	if not fields(value, ["protocol_version", "type", "event", "epoch", "zone_id", "revision", "data"]) \
		or not integer(value.protocol_version, VERSION, VERSION) or value.type != "event" \
		or not token(value.epoch) or not zone(value.zone_id) or not integer(value.revision, 1):
		return false
	if value.event in ["joined", "moved"]:
		return fields(value.data, ["player"]) and player(value.data.player) and value.data.player.zone_id == value.zone_id
	return value.event == "left" and fields(value.data, ["player_id"]) and token(value.data.player_id)

static func version_error(value: Variant) -> bool:
	if not fields(value, ["type", "bootstrap_version", "code", "received_version", "supported_versions"]) \
		or value.type != "version_error" or not integer(value.bootstrap_version, 1, 1) \
		or value.code != "UNSUPPORTED_VERSION" or not integer(value.received_version, VERSION, VERSION) \
		or not value.supported_versions is Array or value.supported_versions.is_empty() or value.supported_versions.size() > 8:
		return false
	var previous := 0
	for item in value.supported_versions:
		if not integer(item, previous + 1) or item == VERSION:
			return false
		previous = item
	return true
