extends RefCounted
## Public wire validation only. Replica reduction and presentation belong elsewhere.

const VERSION := 6
const MAX_FRAME_BYTES := 65536
const WireJson = preload("res://scripts/mmo/wire_json.gd")
const PUBLIC_OPERATIONS := ["login", "enter", "map", "state", "input", "logout", "world_rules", "session_rules", "ping"]
# Wire codes/status semantics from protocol v6, independently implemented here.
# Internal-only WRITER_BUSY has no legal public rejection operation.
const PUBLIC_ERROR_CODES := [
	"WORLD_PAUSED", "FLUSH_FAILED", "STORAGE_CONFLICT", "WRITER_BUSY", "INVALID_TICKET",
	"NOT_AUTHORIZED", "WRONG_ENDPOINT", "SERVER_UNAVAILABLE", "INVALID_MESSAGE",
	"UNSUPPORTED_VERSION", "UNKNOWN_OPERATION", "MESSAGE_TOO_LARGE", "INVALID_MAP",
	"NOT_AUTHENTICATED", "ALREADY_AUTHENTICATED", "NICKNAME_NOT_ALLOWED", "ALREADY_ONLINE",
	"OUT_OF_BOUNDS", "RATE_LIMITED", "RESOURCE_LIMIT", "TIMEOUT", "STORAGE_ERROR", "INTERNAL_ERROR",
]
const REJECTION_CODES := [
	"NOT_AUTHENTICATED", "ALREADY_AUTHENTICATED", "NICKNAME_NOT_ALLOWED", "ALREADY_ONLINE",
	"RATE_LIMITED", "INVALID_TICKET", "WRITER_BUSY", "WORLD_PAUSED",
]
const REJECTION_OPERATIONS := {
	"WORLD_PAUSED": ["input"],
	"NOT_AUTHENTICATED": ["map", "state", "input", "logout", "world_rules", "ping"],
	"ALREADY_AUTHENTICATED": ["enter"],
	"NICKNAME_NOT_ALLOWED": ["login"],
	"ALREADY_ONLINE": ["enter"],
	"INVALID_TICKET": ["enter"],
	"WRITER_BUSY": [],
	"RATE_LIMITED": PUBLIC_OPERATIONS,
}

static func decode(frame: PackedByteArray) -> Dictionary:
	# TCP removes the delimiter LF; any other raw LF/CR is forbidden in a frame.
	if frame.is_empty() or frame.size() + 1 > MAX_FRAME_BYTES or frame.has(13) or frame.has(10):
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
	if not value is String:
		return false
	var match_result := RegEx.create_from_string(pattern).search(value)
	return match_result != null and match_result.get_string() == value

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
		return failure_response(value)
	if value.status != "ok" or value.error != null or not token(value.request_id):
		return false
	var data: Variant = value.data
	match value.op:
		"login":
			return fields(data, ["ticket", "expires_in_ms", "game_server"]) and digest(data.ticket) \
				and integer(data.expires_in_ms, 1, 30000) and endpoint(data.game_server)
		"enter":
			if not fields(data, ["session_id", "player_id", "bootstrap", "snapshot"]) or not token(data.session_id) \
				or not token(data.player_id) or not bootstrap(data.bootstrap) or not snapshot(data.snapshot) \
				or data.snapshot.epoch != data.bootstrap.identity.realm_instance_id:
				return false
			for item in data.snapshot.players:
				if item.player_id == data.player_id:
					return true
			return false
		"map":
			return fields(data, ["identity", "map"]) and identity(data.identity) and map_definition(data.map)
		"state":
			return fields(data, ["snapshot"]) and snapshot(data.snapshot)
		"world_rules":
			return fields(data, ["identity", "movement"]) and identity(data.identity) \
				and fields(data.movement, ["step_units", "min_move_interval_ms"]) \
				and integer(data.movement.step_units, 1, 1) and integer(data.movement.min_move_interval_ms, 1, 60000)
		"session_rules":
			return fields(data, ["min_request_interval_ms", "idle_timeout_ms", "keepalive_interval_ms"]) \
				and integer(data.min_request_interval_ms, 1, 60000) and integer(data.idle_timeout_ms, 1, 3600000) \
				and integer(data.keepalive_interval_ms, data.min_request_interval_ms + 1, int(data.idle_timeout_ms / 2))
		"ping":
			return fields(data, ["pong"]) and data.pong is bool and data.pong
		"input":
			return fields(data, ["epoch", "zone_id", "player_id", "input_seq", "x"]) \
				and token(data.epoch) and zone(data.zone_id) and token(data.player_id) \
				and integer(data.input_seq, 1) and integer(data.x)
		"logout":
			return fields(data, ["flush"]) and fields(data.flush, ["status", "save_version"]) \
				and ((data.flush.status == "completed" and integer(data.flush.save_version)) \
					or (data.flush.status == "disabled" and data.flush.save_version == null))
	return false

static func failure_response(value: Dictionary) -> bool:
	if value.data != null or not fields(value.error, ["code", "message"]):
		return false
	var code: Variant = value.error.code
	var message: Variant = value.error.message
	if not code is String or not code in PUBLIC_ERROR_CODES or not message is String \
		or message.length() < 1 or message.length() > 256 \
		or RegEx.create_from_string("[\\x00-\\x1f\\x7f]").search(message):
		return false
	if (value.status == "rejected") != (code in REJECTION_CODES):
		return false
	var correlated: bool = token(value.request_id) and value.op in PUBLIC_OPERATIONS
	if not correlated and not (value.request_id == null and value.op == null):
		return false
	if value.status == "rejected" and (not correlated or not value.op in REJECTION_OPERATIONS[code]):
		return false
	if code == "FLUSH_FAILED" and (not correlated or value.op != "logout"):
		return false
	# This code is legal only in the stable version_error bootstrap envelope.
	return code != "UNSUPPORTED_VERSION"

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

static func identity(value: Variant) -> bool:
	return fields(value, ["game_card_id", "realm_id", "realm_instance_id"]) and token(value.game_card_id) \
		and token(value.realm_id) and token(value.realm_instance_id)

static func bootstrap(value: Variant) -> bool:
	if not fields(value, ["identity", "capabilities"]) or not identity(value.identity) \
		or not value.capabilities is Array or value.capabilities.size() > 32:
		return false
	var previous := ""
	for item in value.capabilities:
		if not item is String or item.length() > 128 or not matches(item, "^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,127}$") or item <= previous:
			return false
		previous = item
	return true
