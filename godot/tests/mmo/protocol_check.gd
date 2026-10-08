extends SceneTree

const Protocol = preload("res://scripts/mmo/protocol_v8.gd")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	check(Protocol.decode('{"x":9007199254740991}'.to_utf8_buffer()).get("x") == 9007199254740991, "max integer")
	check(Protocol.decode('{"nested":[true,false,null,{"x":"\\u0061"}]}'.to_utf8_buffer()).get("nested") == [true, false, null, {"x": "a"}], "strict JSON values")
	for source in ['{"x":1,"x":2}', '{"x":1,"\\u0078":2}', '{"x":1,}', '{"x":[1,]}', '{"x":1.0}', '{"x":1e0}', '{"x":01}', '{"x":9007199254740992}', '{"x":NaN}', '{"x":"\\ud800"}', '{"x":"\\udc00"}', '{"x":"\\q"}', '{"x":"\t"}', '\ufeff{"x":1}', '{"x":1}\r', '[1]', '{"x":1}junk', '{"x":']:
		check(Protocol.decode(source.to_utf8_buffer()).is_empty(), "invalid JSON rejected")
	check(Protocol.decode(('{"x":' + '['.repeat(17) + '0' + ']'.repeat(17) + '}').to_utf8_buffer()).is_empty(), "depth bound")
	check(Protocol.decode(PackedByteArray([123, 34, 120, 34, 58, 34, 255, 34, 125])).is_empty(), "invalid UTF8")
	check(Protocol.decode((' '.repeat(65536) + '{}').to_utf8_buffer()).is_empty(), "frame bound")
	check(Protocol.decode('{"x":"\\ud83d\\ude00"}'.to_utf8_buffer()).get("x") == "😀", "valid surrogate pair")
	var map := {"schema_version": 1, "map_id": "city/apartment", "content_version": 1,
		"min_x": 0, "max_x": 100, "spawn_x": 50, "units_per_meter": 1,
		"content_hash": "4f465435cbb8eb3e5154a4776be29e7aee4f73376e00fb26299bfbf0cfcd361b"}
	check(Protocol.map_definition(map), "server canonical hash")
	var bad_map: Dictionary = map.duplicate()
	bad_map.max_x = 101
	check(not Protocol.map_definition(bad_map), "modified map hash rejected")
	bad_map = map.duplicate()
	bad_map.min_x = true
	check(not Protocol.map_definition(bad_map), "bool is not integer")
	check(not Protocol.endpoint({"host": "http://localhost", "port": 7777, "server_id": "g"}), "no URL endpoint")
	var bootstrap := {"type": "version_error", "bootstrap_version": 1, "code": "UNSUPPORTED_VERSION", "received_version": 8, "supported_versions": [4]}
	check(Protocol.version_error(bootstrap), "bootstrap version mismatch")
	bootstrap.supported_versions = [8]
	check(not Protocol.version_error(bootstrap), "invalid bootstrap rejected")
	for source in ['{"x":\r1}', '{"x":1}\r ', '{"x":1}\r', '{"x":\n1}']:
		check(Protocol.decode(source.to_utf8_buffer()).is_empty(), "raw CR/LF anywhere rejected")
	check(Protocol.decode('{"x":"\\r\\n"}'.to_utf8_buffer()).get("x") == "\r\n", "escaped CR/LF remains legal JSON")
	for item in [
		["OUT_OF_BOUNDS", "control_set", "rejected", false],
		["ALREADY_ONLINE", "enter", "rejected", true],
		["ALREADY_ONLINE", "map", "rejected", false],
		["NICKNAME_NOT_ALLOWED", "login", "error", false],
		["MADE_UP_ERROR", "login", "rejected", false],
		["MADE_UP_ERROR", "login", "error", false],
		["FLUSH_FAILED", "logout", "error", true],
		["FLUSH_FAILED", "state", "error", false],
		["FLUSH_FAILED", null, "error", false],
		["FLUSH_FAILED", "logout", "rejected", false],
		["UNSUPPORTED_VERSION", "login", "error", false],
		["WORLD_PAUSED", "control_set", "rejected", true],
		["WORLD_PAUSED", "state", "rejected", false],
		["RATE_LIMITED", "control_set", "rejected", true],
		["RATE_LIMITED", "login", "error", false],
		["WRITER_BUSY", "enter", "rejected", false],
		["INVALID_MESSAGE", null, "error", true],
		["ALREADY_ONLINE", null, "rejected", false],
	]:
		check(Protocol.response(failure(item[0], item[1], item[2])) == item[3], "code/status/operation semantics")
	for op in Protocol.PUBLIC_OPERATIONS:
		check(Protocol.response(failure("RATE_LIMITED", op, "rejected")), "rate limit public operations")
	var partial := failure("INTERNAL_ERROR", "login", "error")
	partial.request_id = null
	check(not Protocol.response(partial), "partial correlation rejected")
	var frame_player := {"player_id":"p1", "position_mm":1000, "velocity_mm_s":0, "facing":1,
		"last_applied_control_seq":1,"control_started_tick":0, "contacts":[], "contact_delta_velocity_mm_s":0,
		"contact_response_facing":0, "contact_response_tick":0, "contact_response_contacts":[]}
	check(Protocol.motion_frame_player(frame_player, 4), "empty physical response is explicit and valid")
	var response := frame_player.duplicate(true)
	response.contact_delta_velocity_mm_s = 1200
	response.contact_response_facing = 1
	response.contact_response_tick = 3
	response.contact_response_contacts = ["p2"]
	check(Protocol.motion_frame_player(response, 4), "bounded peer response fact is valid")
	response.contact_response_tick = 5
	check(not Protocol.motion_frame_player(response, 4), "future contact response tick rejected")
	response = frame_player.duplicate(true)
	response.contact_delta_velocity_mm_s = 1200
	check(not Protocol.motion_frame_player(response, 4), "incomplete contact response rejected")
	print(JSON.stringify({"suite": "protocol", "checks": _checks, "failures": _failures, "result": "PASS" if _failures == 0 else "FAIL"}))
	quit(0 if _failures == 0 else 1)

func failure(code: String, op: Variant, status: String) -> Dictionary:
	return {"protocol_version": 8, "type": "response", "request_id": "r1" if op != null else null,
		"op": op, "status": status, "data": null, "error": {"code": code, "message": "Test rejection"}}

func check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		printerr("FAIL: ", label)
