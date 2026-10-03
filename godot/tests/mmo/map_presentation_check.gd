extends SceneTree
const Protocol = preload("res://scripts/mmo/protocol_v6.gd")
const Cache = preload("res://scripts/mmo/map_cache.gd")
const Platform = preload("res://scripts/presentation/platform_world.gd")
var failures: Array[String] = []
var assertions := 0
var options: Dictionary = {}
var client: Node
var maps_received := 0
var evidence: Array = []
var deadline := 0
var finished := false

func _initialize() -> void:
	start.call_deferred()

func check(condition: bool, reason: String) -> void:
	assertions += 1
	if not condition:
		failures.append(reason)

func definition(id: String, low: int, high: int, spawn: int, units: int = 1) -> Dictionary:
	var value := {"schema_version": 1, "map_id": id, "content_version": 1,
		"min_x": low, "max_x": high, "spawn_x": spawn, "units_per_meter": units}
	value.content_hash = JSON.stringify(value, "", true).sha256_text()
	return value

func reference(value: Dictionary) -> Dictionary:
	return {"map_id": value.map_id, "content_version": value.content_version, "content_hash": value.content_hash}

func view(value: Dictionary, x: int) -> Dictionary:
	return {"map": reference(value), "confirmed_local_x": x}

func write_file(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "CORRUPT_FILE_OPEN")
	if file != null:
		file.store_string(content)
		file.close()

func start() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	deadline = Time.get_ticks_msec() + 20000
	if options.get("mode", "unit") == "unit":
		await unit_checks()
	else:
		await stream_checks()
	finish()

func unit_checks() -> void:
	var cache := Cache.new()
	cache.directory = "user://unit-maps"
	var map := definition("city/apartment", 0, 100, 50)
	var ref := reference(map)
	check(cache.load_verified(ref).is_empty(), "COLD_MISS")
	check(cache.store_verified(map, ref), "STORE_VERIFIED")
	check(cache.load_verified(ref) == map, "ROUND_TRIP")
	var changed := cache.load_verified(ref)
	changed.max_x = 99
	check(cache.load_verified(ref).max_x == 100, "DEFENSIVE_LOAD")
	check(not cache.store_verified(changed, ref), "BAD_HASH_NOT_STORED")
	var next := map.duplicate()
	next.content_version = 2
	check(cache.path_for(reference(next)) != cache.path_for(ref), "VERSION_KEY")
	check(cache.load_verified(reference(next)).is_empty(), "VERSION_MISS")
	check(cache.path_for({"map_id": "../../escape"}).is_empty(), "SAFE_PATH")
	for kind in ["hash", "schema", "reference", "duplicate", "oversized", "float", "truncated"]:
		var bad := map.duplicate()
		var content := ""
		match kind:
			"hash": bad.max_x = 101
			"schema": bad.schema_version = 2
			"reference": bad = definition("city/street", 0, 200, 100)
			"duplicate": content = '{"schema_version":1,"schema_version":1}'
			"oversized": content = " ".repeat(65537)
			"float": content = JSON.stringify(map).replace('"min_x":0', '"min_x":0.0')
			"truncated": content = '{"schema_version":'
		write_file(cache.path_for(ref), JSON.stringify(bad) if content.is_empty() else content)
		check(cache.load_verified(ref).is_empty(), "UNTRUSTED_CACHE_" + kind)
		check(cache.store_verified(map, ref), "REPAIR_" + kind)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(458, 116)
	root.add_child(viewport)
	var platform := Platform.new()
	platform.set_movement_rules({"movement":{"step_units":1,"min_move_interval_ms":200}})
	viewport.add_child(platform)
	for item in [definition("city/apartment", 0, 100, 50), definition("city/street", 0, 200, 100), definition("city/work", 10, 60, 30), definition("city/scaled", 100, 1100, 600, 10)]:
		check(platform.project(item, view(item, item.spawn_x)), "PROJECT_" + item.map_id)
		check(is_equal_approx(platform.server_to_pixel(item.min_x), 32), "MIN_ORIGIN")
		check(is_equal_approx(platform.server_to_pixel(item.max_x), 32 + platform.world_length), "MAX_WALL")
		check(is_equal_approx(platform.sprite.position.x, platform.server_to_pixel(item.spawn_x)), "SPAWN_PROJECTION")
		check(platform.terrain.get_used_cells().size() <= 32, "BOUNDED_TILES")
		var marks := platform.ruler_marks()
		check(not marks.is_empty() and marks.size() <= 60, "RULER_VISIBLE_BOUNDED")
		var valid_marks := true
		for mark in marks:
			valid_marks = valid_marks and mark.x >= item.min_x and mark.x <= item.max_x and is_equal_approx(mark.pixel, platform.server_to_pixel(mark.x))
		check(valid_marks, "RULER_ABSOLUTE_X_AND_SCALE")
		check(platform.sprite.get_script() == null, "NO_LEGACY_CONTROLLER")
		var saved_x: float = platform.sprite.position.x
		var key := InputEventKey.new()
		key.keycode = KEY_D
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame
		key.pressed = false
		Input.parse_input_event(key)
		check(platform.sprite.position.x == saved_x, "INPUT_CANNOT_CHANGE_CONFIRMED_X")
		check(platform.project(item, view(item, item.min_x)), "PROJECT_LEFT_BOUNDARY")
		check(platform.project(item, view(item, item.max_x)), "PROJECT_RIGHT_BOUNDARY")
	viewport.size = Vector2i(320, 116)
	await process_frame
	check(platform.terrain.get_used_cells().size() <= 23, "RESIZE_REBUILDS_VISIBLE_STRIP")
	check(not platform.project(map, view(map, 101)), "OUTSIDE_MAP_NOT_RENDERED")
	var huge := definition("city/huge", 0, 9007199254740991, 0)
	check(platform.project(huge, view(huge, 0)) and platform.terrain.get_used_cells().size() <= 32, "HUGE_MAP_BOUNDED")
	check(platform.ruler_marks().size() <= 42, "HUGE_MAP_RULER_BOUNDED")
	viewport.queue_free()

func wait_state(target: String) -> void:
	while not finished and client.state != target and client.state != "FAILED":
		await process_frame
	check(client.state == target, "STATE_" + target)

func stream_checks() -> void:
	client = root.get_node("MmoClient")
	client.response_received.connect(func(op: String, _data: Dictionary):
		if op == "map": maps_received += 1)
	var cycles := ["cold", "warm", "hash", "schema", "duplicate", "oversized", "reference"]
	for cycle in cycles:
		if finished:
			return
		check(client.connect_world("127.0.0.1", int(options.port), options.get("nickname", "player1")), "CONNECT_" + cycle)
		await wait_state("READY")
		if client.state != "READY":
			return
		var map: Dictionary = client.map_document
		check(client.map_source == ("cache" if cycle == "warm" else "server"), "SOURCE_" + cycle)
		if options.has("zone"):
			check(map.map_id == options.zone, "ZONE_FROM_SERVER")
		if options.has("length"):
			check((map.max_x - map.min_x) * 8 / map.units_per_meter == int(options.length), "ZONE_LENGTH")
		change_scene_to_file("res://scenes/mmo/world.tscn")
		await process_frame
		await process_frame
		var world: Control = current_scene
		check(world.platform != null and is_equal_approx(world.platform.sprite.position.x, world.platform.server_to_pixel(client.world_replica.local_player().x)), "CONFIRMED_SPRITE")
		var cells: int = world.platform.terrain.get_used_cells().size()
		var pixels: float = minf(world.platform.world_length, world.platform.get_viewport_rect().size.x)
		check(cells * 16 >= pixels - 16 and cells <= 32, "VIEWPORT_PLATFORM_COVERAGE")
		check(client.map_cache.load_verified(client.world_replica.view().map) == map, "VERIFIED_DISK_" + cycle)
		evidence.append({"cycle":cycle,"source":client.map_source,"zone":map.map_id,"world_length":world.platform.world_length,"sprite_x":world.platform.sprite.position.x})
		if options.has("capture") and cycle == "cold":
			await create_timer(0.15).timeout
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(options.capture) == OK, "SCREENSHOT")
		var path: String = client.map_cache.path_for(reference(map))
		check(client.logout(), "LOGOUT_" + cycle)
		await wait_state("DISCONNECTED")
		await process_frame
		# Seed the next cycle's corruption, without touching user saves.
		var index: int = cycles.find(cycle)
		if index + 1 < cycles.size():
			var next: String = cycles[index + 1]
			var bad := map.duplicate()
			var content := ""
			match next:
				"hash": bad.max_x += 1
				"schema": bad.schema_version = 2
				"duplicate": content = '{"schema_version":1,"schema_version":1}'
				"oversized": content = " ".repeat(65537)
				"reference": bad = definition("city/other", 0, 100, 50)
			if next != "warm":
				write_file(path, JSON.stringify(bad) if content.is_empty() else content)
	check(maps_received == 6, "ONLY_CACHE_MISSES_REQUEST_MAP")

func _process(_delta: float) -> bool:
	if not finished and deadline != 0 and Time.get_ticks_msec() >= deadline:
		check(false, "OVERALL_TIMEOUT")
		finish()
	return false

func finish() -> void:
	if finished:
		return
	finished = true
	if client != null:
		client.disconnect_world()
	print(JSON.stringify({"suite":"presentation","result":"PASS" if failures.is_empty() else "FAIL","failures":failures,"checks":assertions,"evidence":evidence}))
	quit(0 if failures.is_empty() else 1)
