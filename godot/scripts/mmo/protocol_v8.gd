extends RefCounted
## Public wire validation only. Replica reduction and presentation belong elsewhere.

const VERSION := 8
const MAX_FRAME_BYTES := 65536
const WireJson = preload("res://scripts/mmo/wire_json.gd")
const PUBLIC_OPERATIONS := ["login", "select_realm", "lobby_enter", "lobby_state", "lobby_leave", "character_list", "character_catalog", "character_validate", "character_create", "character_select", "character_delete", "world_enter", "enter", "map", "state", "control_set", "logout", "world_rules", "session_rules", "ping"]
const PUBLIC_ERROR_CODES := ["AUTH_FAILED", "APPEARANCE_INVALID", "APPEARANCE_INCOMPATIBLE", "REGISTRY_UNAVAILABLE", "NAME_TAKEN", "SLOTS_FULL", "CHARACTER_NOT_OWNED", "CHARACTER_DELETED", "CHARACTER_BUSY", "DURABILITY_UNSAFE", "STALE_CHARACTER", "IDEMPOTENCY_CONFLICT", "IDEMPOTENCY_LIMIT", "OUTCOME_UNKNOWN", "INVALID_HANDOFF", "REALM_UNAVAILABLE", "ACCOUNT_NOT_ALLOWED", "WORLD_PAUSED", "FLUSH_FAILED", "STORAGE_CONFLICT", "WRITER_BUSY", "NOT_AUTHORIZED", "WRONG_ENDPOINT", "SERVER_UNAVAILABLE", "INVALID_MESSAGE", "UNSUPPORTED_VERSION", "UNKNOWN_OPERATION", "MESSAGE_TOO_LARGE", "INVALID_MAP", "NOT_AUTHENTICATED", "ALREADY_AUTHENTICATED", "ALREADY_ONLINE", "OUT_OF_BOUNDS", "RATE_LIMITED", "RESOURCE_LIMIT", "TIMEOUT", "STORAGE_ERROR", "INTERNAL_ERROR"]
const REJECTION_CODES := ["ACCOUNT_NOT_ALLOWED", "ALREADY_AUTHENTICATED", "ALREADY_ONLINE", "APPEARANCE_INCOMPATIBLE", "APPEARANCE_INVALID", "AUTH_FAILED", "CHARACTER_BUSY", "CHARACTER_DELETED", "CHARACTER_NOT_OWNED", "DURABILITY_UNSAFE", "IDEMPOTENCY_CONFLICT", "IDEMPOTENCY_LIMIT", "INVALID_HANDOFF", "NAME_TAKEN", "NOT_AUTHENTICATED", "RATE_LIMITED", "REALM_UNAVAILABLE", "REGISTRY_UNAVAILABLE", "SLOTS_FULL", "STALE_CHARACTER", "WORLD_PAUSED", "WRITER_BUSY"]
const REJECTION_OPERATIONS := {"AUTH_FAILED": ["login"], "APPEARANCE_INVALID": ["character_create", "character_validate"], "APPEARANCE_INCOMPATIBLE": ["character_create", "character_delete", "character_list", "character_select", "character_validate", "enter", "world_enter"], "REGISTRY_UNAVAILABLE": ["character_create", "character_delete", "character_list", "character_select", "enter", "world_enter"], "NAME_TAKEN": ["character_create"], "SLOTS_FULL": ["character_create"], "CHARACTER_NOT_OWNED": ["character_delete", "character_select", "enter", "world_enter"], "CHARACTER_DELETED": ["character_delete", "character_select", "enter", "world_enter"], "CHARACTER_BUSY": ["character_delete", "character_select", "enter", "world_enter"], "DURABILITY_UNSAFE": ["character_delete", "character_select", "enter", "world_enter"], "STALE_CHARACTER": ["character_delete", "enter", "world_enter"], "IDEMPOTENCY_CONFLICT": ["character_create", "character_delete"], "IDEMPOTENCY_LIMIT": ["character_create", "character_delete"], "INVALID_HANDOFF": ["enter", "lobby_enter"], "REALM_UNAVAILABLE": ["select_realm"], "ACCOUNT_NOT_ALLOWED": ["login"], "WORLD_PAUSED": ["control_set"], "NOT_AUTHENTICATED": ["character_catalog", "character_create", "character_delete", "character_list", "character_select", "character_validate", "control_set", "lobby_leave", "lobby_state", "logout", "map", "ping", "select_realm", "state", "world_enter", "world_rules"], "ALREADY_AUTHENTICATED": ["enter", "lobby_enter", "login"], "ALREADY_ONLINE": ["enter"], "WRITER_BUSY": [], "RATE_LIMITED": ["character_catalog", "character_create", "character_delete", "character_list", "character_select", "character_validate", "enter", "control_set", "lobby_enter", "lobby_leave", "lobby_state", "login", "logout", "map", "ping", "select_realm", "session_rules", "state", "world_enter", "world_rules"]}

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
	return fields(value, ["host", "port"]) \
		and matches(value.host, "^[A-Za-z0-9.:-]{1,253}$") and integer(value.port, 1, 65535)

static func motion(value: Variant) -> bool:
	return fields(value, ["position_mm", "velocity_mm_s", "facing", "last_applied_control_seq", "simulation_tick", "control_started_tick"]) \
		and integer(value.position_mm, -1000000000, 1000000000) and integer(value.velocity_mm_s, -50000, 50000) \
		and value.facing in [-1, 1] and integer(value.facing, -1, 1) \
		and integer(value.last_applied_control_seq) and integer(value.simulation_tick) \
		and integer(value.control_started_tick, 0, int(value.simulation_tick))

static func motion_frame_player(value: Variant, frame_tick: int) -> bool:
	if not fields(value, ["player_id", "position_mm", "velocity_mm_s", "facing", "last_applied_control_seq", "control_started_tick", "contacts", \
		"contact_delta_velocity_mm_s", "contact_response_facing", "contact_response_tick", "contact_response_contacts", "contact_impact_sources"]) \
		or not token(value.player_id) or not integer(value.position_mm, -1000000000, 1000000000) \
		or not integer(value.velocity_mm_s, -50000, 50000) or not integer(value.facing, -1, 1) or value.facing not in [-1, 1] \
		or not integer(value.last_applied_control_seq) or not integer(value.control_started_tick, 0, frame_tick) or not value.contacts is Array or value.contacts.size() > 65 \
		or not integer(value.contact_delta_velocity_mm_s, -100000, 100000) \
		or not integer(value.contact_response_facing, -1, 1) \
		or not integer(value.contact_response_tick, 0, frame_tick) \
		or not value.contact_response_contacts is Array or value.contact_response_contacts.size() > 63 \
		or not value.contact_impact_sources is Array or value.contact_impact_sources.size() > 63:
		return false
	var previous := ""
	for contact in value.contacts:
		if not token(contact) or contact <= previous: return false
		previous = contact
	previous = ""
	for contact in value.contact_response_contacts:
		if not token(contact) or contact in ["wall_min", "wall_max"] or contact <= previous: return false
		previous = contact
	previous = ""
	for source in value.contact_impact_sources:
		if not token(source) or source <= previous or source == value.player_id or not source in value.contact_response_contacts: return false
		previous = source
	var has_response := int(value.contact_delta_velocity_mm_s) != 0
	if (not value.contact_impact_sources.is_empty() and not has_response) \
		or has_response != (not value.contact_response_contacts.is_empty()) \
		or has_response != (int(value.contact_response_facing) in [-1, 1]) \
		or has_response != (int(value.contact_response_tick) > 0):
		return false
	return true

static func player(value: Variant) -> bool:
	if not fields(value, ["player_id", "nickname", "zone_id", "motion", "contacts", "character", "physics"]) \
		or not token(value.player_id) or not display_name(value.nickname) or not zone(value.zone_id) \
		or not motion(value.motion) or not value.contacts is Array or value.contacts.size() > 65 \
		or not presentation(value.character) or not physics_binding(value.physics) or value.character.character_id != value.player_id or value.character.display_name != value.nickname:
		return false
	var previous := ""
	for contact in value.contacts:
		if not token(contact) or contact <= previous: return false
		previous = contact
	return true

static func physics_profile(value: Variant) -> bool:
	if not fields(value, ["character_model_id", "physics_profile_revision", "body", "motor"]) \
		or not token(value.character_model_id) or not token(value.physics_profile_revision): return false
	var body: Variant = value.body
	var motor: Variant = value.motor
	if not fields(body, ["body_profile_id", "mass_g", "collision_width_mm", "collision_height_mm"]) \
		or not token(body.body_profile_id) or not integer(body.mass_g, 10000, 500000) \
		or not integer(body.collision_width_mm, 2, 10000) or int(body.collision_width_mm) % 2 != 0 \
		or not integer(body.collision_height_mm, 1, 10000): return false
	return fields(motor, ["motor_profile_id", "drive_force_mN", "brake_force_mN", "top_speed_mm_s"]) \
		and token(motor.motor_profile_id) and integer(motor.drive_force_mN, 0, 2000000) \
		and integer(motor.brake_force_mN, 0, 2000000) and integer(motor.top_speed_mm_s, 1, 50000) \
		and maxi(int(motor.drive_force_mN), int(motor.brake_force_mN)) * 1000 <= int(body.mass_g) * 50000

static func physics_binding(value: Variant) -> bool:
	return fields(value, ["physics_profile_revision", "body_profile_id", "motor_profile_id"]) \
		and token(value.physics_profile_revision) and token(value.body_profile_id) and token(value.motor_profile_id)

static func selected_physics(movement_rules: Dictionary, player_value: Dictionary) -> Dictionary:
	for profile in movement_rules.physics_profiles:
		if profile.character_model_id == player_value.character.appearance_payload.character_model_id \
			and profile.physics_profile_revision == player_value.physics.physics_profile_revision \
			and profile.body.body_profile_id == player_value.physics.body_profile_id \
			and profile.motor.motor_profile_id == player_value.physics.motor_profile_id:
			return profile.duplicate(true)
	return {}

static func movement(value: Variant) -> bool:
	if not fields(value, ["physics_hz", "publication_hz", "control_interval_ms", "engage_ms", "physics_profiles"]) \
		or not integer(value.engage_ms, 1, 1000) or value.physics_hz != 60 or value.publication_hz != 20 \
		or value.control_interval_ms != 50 or not value.physics_profiles is Array \
		or value.physics_profiles.is_empty() or value.physics_profiles.size() > 32: return false
	var models: Dictionary = {}
	var revision := ""
	for profile in value.physics_profiles:
		if not physics_profile(profile) or models.has(profile.character_model_id): return false
		if revision != "" and revision != profile.physics_profile_revision: return false
		revision = profile.physics_profile_revision
		models[profile.character_model_id] = true
	return true

static func map_reference(value: Variant) -> bool:
	return fields(value, ["map_id", "content_version", "content_hash"]) and zone(value.map_id) \
		and integer(value.content_version, 1) and digest(value.content_hash)

static func snapshot(value: Variant) -> bool:
	if not fields(value, ["epoch", "revision", "map", "players"]) or not token(value.epoch) \
		or not integer(value.revision) or not map_reference(value.map) or not value.players is Array \
		or value.players.is_empty() or value.players.size() > 64:
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
			return login_result(data)
		"select_realm":
			return fields(data, ["realm_handoff", "expires_in_ms", "realm"]) and digest(data.realm_handoff) \
				and integer(data.expires_in_ms, 1, 30000) and descriptor(data.realm) and data.realm.status == "online"
		"lobby_enter", "lobby_state":
			return lobby_result(data)
		"lobby_leave":
			return fields(data, ["left"]) and data.left is bool and data.left
		"character_list":
			return roster_result(data)
		"character_catalog":
			return fields(data, ["game_card_id", "realm_id", "catalog"]) and token(data.game_card_id) and token(data.realm_id) \
				and catalog(data.catalog) and data.catalog.game_card_id == data.game_card_id
		"character_validate":
			return fields(data, ["game_card_id", "realm_id", "definition"]) and token(data.game_card_id) and token(data.realm_id) \
				and fields(data.definition, ["appearance_schema_version", "appearance_payload"]) and integer(data.definition.appearance_schema_version, 1) and appearance(data.definition.appearance_payload)
		"character_create", "character_select":
			return fields(data, ["character", "character_generation"]) and character_record(data.character) and integer(data.character_generation, 1)
		"character_delete":
			return fields(data, ["game_card_id", "realm_id", "character_id", "character_generation", "lifecycle_state"]) \
				and token(data.game_card_id) and token(data.realm_id) and token(data.character_id) and integer(data.character_generation, 2) and data.lifecycle_state == "deleted"
		"world_enter":
			return fields(data, ["world_handoff", "expires_in_ms", "character_id", "identity", "game"]) and digest(data.world_handoff) \
				and integer(data.expires_in_ms, 1, 30000) and token(data.character_id) and identity(data.identity) and endpoint(data.game)
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
			return fields(data, ["identity", "movement"]) and identity(data.identity) and movement(data.movement)
		"session_rules":
			return fields(data, ["min_request_interval_ms", "idle_timeout_ms", "keepalive_interval_ms"]) \
				and integer(data.min_request_interval_ms, 1, 60000) and integer(data.idle_timeout_ms, 1, 3600000) \
				and integer(data.keepalive_interval_ms, data.min_request_interval_ms + 1, int(data.idle_timeout_ms / 2))
		"ping":
			return fields(data, ["pong"]) and data.pong is bool and data.pong
		"control_set":
			return fields(data, ["epoch", "zone_id", "player_id", "control_seq", "accepted"]) \
				and token(data.epoch) and zone(data.zone_id) and token(data.player_id) \
				and integer(data.control_seq, 1) and data.accepted is bool and data.accepted
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

static func damage_event(data: Variant) -> bool:
	if not fields(data, ["event_id", "event_seq", "zone_generation", "simulation_tick",
		"target_entity_id", "source_entity_id", "position_mm",
		"impact_impulse_g_mm_s", "damage", "cause"]):
		return false
	return integer(data.event_seq, 1) and data.event_id == "damage_" + str(data.event_seq) \
		and integer(data.zone_generation, 1) and integer(data.simulation_tick, 1) \
		and token(data.target_entity_id) and token(data.source_entity_id) \
		and data.target_entity_id != data.source_entity_id \
		and integer(data.position_mm, -1000000000, 1000000000) \
		and integer(data.impact_impulse_g_mm_s, 1, 50000000000) \
		and integer(data.damage, 1, 9999) and data.cause == "body_collision"

static func event(value: Variant) -> bool:
	if not fields(value, ["protocol_version", "type", "event", "epoch", "zone_id", "revision", "data"]) \
		or not integer(value.protocol_version, VERSION, VERSION) or value.type != "event" \
		or not token(value.epoch) or not zone(value.zone_id) or not integer(value.revision, 1):
		return false
	if value.event == "damage_resolved":
		return damage_event(value.data)
	if value.event == "joined":
		return fields(value.data, ["player"]) and player(value.data.player) and value.data.player.zone_id == value.zone_id
	if value.event == "motion_frame":
		var data: Variant = value.data
		if not fields(data, ["realm_instance_id", "zone_package_id", "zone_generation", "frame_seq", "simulation_tick", "players"]) \
			or data.realm_instance_id != value.epoch or data.zone_package_id != value.zone_id \
			or not integer(data.zone_generation, 1) or not integer(data.frame_seq, 1) \
			or not integer(data.simulation_tick) or not data.players is Array or data.players.is_empty() or data.players.size() > 64:
			return false
		var last_id := ""
		for sample in data.players:
			if not motion_frame_player(sample, data.simulation_tick) or sample.player_id <= last_id: return false
			last_id = sample.player_id
		return true
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

static func display_name(value: Variant) -> bool:
	return value is String and value.length() >= 1 and value.length() <= 64 and RegEx.create_from_string("[\\x00-\\x1f\\x7f]").search(value) == null

static func descriptor(value: Variant) -> bool:
	return fields(value, ["game_card_id", "realm_id", "display_name", "status", "lobby", "policy_version"]) \
		and token(value.game_card_id) and token(value.realm_id) and display_name(value.display_name) \
		and value.status in ["online", "full", "closed", "unavailable"] and endpoint(value.lobby) and integer(value.policy_version, 1)

static func login_result(value: Variant) -> bool:
	if not fields(value, ["account_id", "realms"]) or not token(value.account_id) or not value.realms is Array or value.realms.size() < 1 or value.realms.size() > 16:
		return false
	var seen := {}
	for realm in value.realms:
		if not descriptor(realm): return false
		var key: String = realm.game_card_id + "/" + realm.realm_id
		if seen.has(key): return false
		seen[key] = true
	return true

static func session_rules(value: Variant) -> bool:
	return fields(value, ["min_request_interval_ms", "idle_timeout_ms", "keepalive_interval_ms"]) \
		and integer(value.min_request_interval_ms, 1, 60000) and integer(value.idle_timeout_ms, 1, 3600000) \
		and integer(value.keepalive_interval_ms, value.min_request_interval_ms + 1, int(value.idle_timeout_ms / 2))

static func lobby_result(value: Variant) -> bool:
	if not fields(value, ["lobby_session", "world_availability", "session_rules"]): return false
	var binding: Variant = value.lobby_session
	if not fields(binding, ["account_id", "game_card_id", "realm_id", "lobby_session_id", "lobby_generation"]): return false
	for key in ["account_id", "game_card_id", "realm_id"]:
		if not token(binding[key]): return false
	return digest(binding.lobby_session_id) and integer(binding.lobby_generation, 1) and session_rules(value.session_rules) and \
		value.world_availability in [{"status": "online", "reason": null}, {"status": "unavailable", "reason": "GAME_UNAVAILABLE"}, {"status": "unavailable", "reason": "WORLD_ADMISSION_PENDING"}]

static func appearance(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 16 or JSON.stringify(value).to_utf8_buffer().size() > 1024: return false
	for key in value:
		if not token(key) or not token(value[key]): return false
	return true

static func presentation(value: Variant) -> bool:
	return fields(value, ["game_card_id", "realm_id", "character_id", "display_name", "appearance_schema_version", "appearance_payload"]) \
		and token(value.game_card_id) and token(value.realm_id) and token(value.character_id) and display_name(value.display_name) \
		and integer(value.appearance_schema_version, 2, 2) and appearance(value.appearance_payload)

static func character_record(value: Variant) -> bool:
	if not fields(value, ["game_card_id", "realm_id", "account_id", "character_id", "slot", "display_name", "lifecycle_state", "character_schema_version", "appearance_schema_version", "appearance_payload", "initial_spawn_profile", "created_at_ms", "updated_at_ms"]): return false
	for key in ["game_card_id", "realm_id", "account_id", "character_id", "initial_spawn_profile"]:
		if not token(value[key]): return false
	return value.account_id != value.character_id and integer(value.slot, 1, 16) and display_name(value.display_name) \
		and value.lifecycle_state == "active" and integer(value.character_schema_version, 1, 1) \
		and integer(value.appearance_schema_version, 2, 2) and appearance(value.appearance_payload) \
		and integer(value.created_at_ms, 1) and integer(value.updated_at_ms, value.created_at_ms)

static func roster_result(value: Variant) -> bool:
	if not fields(value, ["game_card_id", "realm_id", "account_id", "slot_limit", "characters"]) or not integer(value.slot_limit, 1, 16) or not value.characters is Array or value.characters.size() > value.slot_limit: return false
	for key in ["game_card_id", "realm_id", "account_id"]:
		if not token(value[key]): return false
	var ids := {}
	var previous := 0
	for record in value.characters:
		if not character_record(record) or ids.has(record.character_id) or record.slot <= previous or record.slot > value.slot_limit: return false
		for key in ["game_card_id", "realm_id", "account_id"]:
			if value[key] != record[key]: return false
		ids[record.character_id] = true
		previous = record.slot
	return true

static func identifiers(value: Variant, limit: int) -> bool:
	if not value is Array or value.is_empty() or value.size() > limit: return false
	var seen := {}
	for item in value:
		if not token(item) or seen.has(item): return false
		seen[item] = true
	return true

static func catalog(value: Variant) -> bool:
	if not fields(value, ["game_card_id", "catalog_version", "appearance_schema_version", "character_models", "default_character_model_id", "initial_spawn_profiles", "default_spawn_profile"]) \
		or not token(value.game_card_id) or not integer(value.catalog_version, 2, 2) or not integer(value.appearance_schema_version, 2, 2) \
		or not value.character_models is Dictionary or value.character_models.is_empty() or value.character_models.size() > 16: return false
	for character_model_id in value.character_models:
		var model: Variant = value.character_models[character_model_id]
		if not token(character_model_id) or not fields(model, ["options", "default_payload"]) \
			or not model.options is Dictionary or model.options.is_empty() or model.options.size() > 15 \
			or model.options.has("character_model_id") or not appearance(model.default_payload) \
			or model.default_payload.size() != model.options.size() + 1 or model.default_payload.get("character_model_id") != character_model_id: return false
		for key in model.options:
			if not token(key) or not identifiers(model.options[key], 32) or not model.default_payload.get(key) in model.options[key]: return false
	return token(value.default_character_model_id) and value.character_models.has(value.default_character_model_id) \
		and identifiers(value.initial_spawn_profiles, 16) and token(value.default_spawn_profile) \
		and value.default_spawn_profile in value.initial_spawn_profiles and JSON.stringify(value).to_utf8_buffer().size() <= 8192
