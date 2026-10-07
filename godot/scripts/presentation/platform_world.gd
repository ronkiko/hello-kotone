extends Node2D
## Confirmed replica projection plus owner-only prediction; server remains authority.
const Protocol = preload("res://scripts/mmo/protocol_v8.gd")
const RemotePlayer = preload("res://scripts/presentation/remote_player.gd")
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const TERRAIN = preload("res://assets/mmo/platform.svg")
const PIXELS_PER_METER := 8.0
const ORIGIN_X := 32.0
const FLOOR_Y := 104.0
const TILE_SIZE := 16
var terrain := TileMapLayer.new()
var camera := Camera2D.new()
var ruler := Node2D.new()
var character_root := CharacterBody2D.new()
var character_collision := CollisionShape2D.new()
var visual_layer := Node2D.new()
var sprite: AnimatedSprite2D
var local_label := Label.new()
var _suspended := false
var remote_players: Dictionary = {}
var world_length := 0.0
var _map: Dictionary = {}
var _view: Dictionary = {}
var _display_x: Variant = null
var _movement: Dictionary = {}
var _position_installed := false
var _first_cell := -1000000
var _bound_nodes: Array[StaticBody2D] = []
var _local_player_id := ""
var _last_applied_control_seq := 0
var _control_history: Array[Dictionary] = []
var _pending_owner_motion: Dictionary = {}
var _pending_snapshot_motion: Dictionary = {}
var _prediction_fenced := false
var _resync_requested := false
var _predicted_contacts: Array[String] = []
var _blend_remaining := 0.0
var _blend_start_offset_x := 0.0
var _prediction_metrics := {"samples": 0, "max_divergence_mm": 0, "last_simulation_tick": -1,
	"small_blends": 0, "snaps": 0, "history_peak": 0, "fences": 0}

func _ready() -> void:
	var atlas := TileSetAtlasSource.new()
	atlas.texture = TERRAIN
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	atlas.create_tile(Vector2i.ZERO)
	atlas.create_tile(Vector2i(1, 0))
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tiles.add_source(atlas, 0)
	terrain.name = "Platform"
	terrain.tile_set = tiles
	terrain.collision_enabled = false
	terrain.navigation_enabled = false
	terrain.position.y = FLOOR_Y
	add_child(terrain)
	ruler.name = "CoordinateRuler"
	ruler.z_index = 3
	ruler.draw.connect(_draw_ruler)
	add_child(ruler)
	character_root.name = "CharacterRoot"
	character_root.position.y = FLOOR_Y
	character_root.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	character_root.safe_margin = 0.001
	character_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	character_root.collision_layer = 2
	character_root.collision_mask = 1
	var initial_shape := RectangleShape2D.new()
	initial_shape.size = Vector2(3.2, 3.2)
	character_collision.shape = initial_shape
	character_collision.position.y = -1.6
	character_root.add_child(character_collision)
	add_child(character_root)
	visual_layer.name = "CharacterVisualLayer"
	visual_layer.scale = Vector2.ONE * Appearance.DISPLAY_SCALE
	visual_layer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	character_root.add_child(visual_layer)
	sprite = AnimatedSprite2D.new()
	visual_layer.add_child(sprite)
	Appearance.Library.install(sprite, "kotone")
	Appearance.pose(sprite, false, 0, 0)
	character_root.z_index = 1
	local_label.position.y = FLOOR_Y - Appearance.display_height_px("kotone") - 18
	local_label.size = Vector2(128, 18)
	local_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	local_label.add_theme_font_size_override("font_size", 11)
	local_label.add_theme_color_override("font_outline_color", Color.BLACK)
	local_label.add_theme_constant_override("outline_size", 3)
	local_label.z_index = 2
	add_child(local_label)
	camera.position.y = 58.0
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()
	get_viewport().size_changed.connect(_resize_projection)
	MmoClient.world_replica.motion_received.connect(_queue_owner_motion)
	MmoClient.world_replica.authoritative_snapshot_received.connect(_queue_snapshot_motion)
	project(_map, _view, _display_x)

func set_movement_rules(rules: Dictionary) -> bool:
	if not Protocol.movement(rules.get("movement")): return false
	_movement = rules.movement.duplicate(true)
	_configure_owner_shape()
	return true

func server_to_pixel(position_mm: int) -> float:
	return ORIGIN_X + (float(position_mm) / 1000.0 - float(_map.min_x) / float(_map.units_per_meter)) * PIXELS_PER_METER

func project(document: Dictionary, view: Dictionary, _unused: Variant = null) -> bool:
	if _movement.is_empty() or not Protocol.map_definition(document) or not Protocol.map_reference(view.get("map")): return false
	for key in ["map_id", "content_version", "content_hash"]:
		if document[key] != view.map[key]: return false
	var players: Variant = view.get("players", {})
	if not players is Dictionary or not players.has(view.get("local_player_id")) or players.size() > 64: return false
	for id in players:
		if not Protocol.player(players[id]) or players[id].player_id != id or players[id].zone_id != document.map_id: return false
	var map_changed := _map.get("map_id", "") != document.map_id or _map.get("content_hash", "") != document.content_hash
	_map = document.duplicate(true)
	_view = view.duplicate(true)
	if map_changed:
		_install_world_bounds()
	world_length = float(document.max_x - document.min_x) / float(document.units_per_meter) * PIXELS_PER_METER
	if not is_node_ready(): return true
	var local: Dictionary = players[view.local_player_id]
	if not _position_installed or _local_player_id != view.local_player_id:
		_local_player_id = view.local_player_id
		_position_installed = true
		_prediction_fenced = false
		_control_history.clear()
		var initial_motion: Dictionary = local.motion.duplicate(true)
		initial_motion["contacts"] = local.contacts.duplicate()
		_apply_authoritative_motion(initial_motion, true)
	local_label.position.x = character_root.position.x - 64
	local_label.text = "%s (you)" % local.nickname
	Appearance.install(sprite, local.character.appearance_payload)
	local_label.position.y = FLOOR_Y - Appearance.display_height_px(local.character.appearance_payload.character_model_id) - 18
	_sync_players()
	_reframe()
	return true

func set_suspended(value: bool) -> void:
	_suspended = value
	if value:
		_pending_owner_motion.clear()
		_control_history.clear()
		_blend_remaining = 0.0
		_blend_start_offset_x = 0.0
		visual_layer.position.x = 0.0
	if sprite != null and value: sprite.pause()
	for node in remote_players.values():
		if value: node.sprite.pause()

func prediction_metrics() -> Dictionary:
	return _prediction_metrics.duplicate(true)

func _configure_owner_shape() -> void:
	if _movement.is_empty(): return
	var width_px := float(_movement.width_mm) * PIXELS_PER_METER / 1000.0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(maxf(width_px, 0.01), maxf(width_px, 0.01))
	character_collision.shape = shape
	character_collision.position = Vector2(0.0, -shape.size.y / 2.0)

func _install_world_bounds() -> void:
	for node in _bound_nodes:
		node.queue_free()
	_bound_nodes.clear()
	if _map.is_empty(): return
	var extent := maxf(256.0, get_viewport_rect().size.y * 4.0)
	for edge in [{"name": "wall_min", "map_x": _map.min_x}, {"name": "wall_max", "map_x": _map.max_x}]:
		var wall := StaticBody2D.new()
		wall.name = str(edge.name)
		wall.position = Vector2(ORIGIN_X + (float(edge.map_x - _map.min_x) / float(_map.units_per_meter)) * PIXELS_PER_METER, FLOOR_Y)
		wall.collision_layer = 1
		wall.collision_mask = 0
		wall.set_meta("contact_id", edge.name)
		var shape := RectangleShape2D.new()
		shape.size = Vector2(0.01, extent)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		wall.add_child(collision)
		add_child(wall)
		_bound_nodes.append(wall)

func _queue_owner_motion(event: Dictionary) -> void:
	if _suspended or _prediction_fenced or event.get("event") != "motion_frame": return
	for sample in event.get("data", {}).get("players", []):
		if sample.get("player_id") == _local_player_id:
			_pending_owner_motion = sample.duplicate(true)
			_pending_owner_motion["simulation_tick"] = event.data.simulation_tick
			return

func _queue_snapshot_motion(snapshot: Dictionary) -> void:
	for player in snapshot.get("players", []):
		if player.get("player_id") == _local_player_id:
			_pending_snapshot_motion = player.motion.duplicate(true)
			_pending_snapshot_motion["contacts"] = player.contacts.duplicate()
			return

func _physics_process(delta: float) -> void:
	if not _pending_snapshot_motion.is_empty():
		var snapshot_motion := _pending_snapshot_motion
		_pending_snapshot_motion = {}
		_pending_owner_motion = {}
		_prediction_fenced = false
		_resync_requested = false
		_apply_authoritative_motion(snapshot_motion, true)
	if not _pending_owner_motion.is_empty():
		var owner_motion := _pending_owner_motion
		_pending_owner_motion = {}
		if not _suspended and not _prediction_fenced:
			_apply_authoritative_motion(owner_motion, false)
	if _suspended or _prediction_fenced or not _position_installed or _movement.is_empty(): return
	var control: Dictionary = MmoClient.prediction_control_state()
	if int(control.control_seq) > _last_applied_control_seq:
		_control_history.append({"control_seq": control.control_seq, "drive": control.drive,
			"facing": control.facing, "at_ms": Time.get_ticks_msec()})
		_prediction_metrics.history_peak = maxi(_prediction_metrics.history_peak, _control_history.size())
		var too_old := not _control_history.is_empty() and Time.get_ticks_msec() - int(_control_history[0].at_ms) > 2000
		if _control_history.size() > 40 or too_old:
			_fence_prediction()
			return
	_integrate_control(control, delta)
	_reframe()

func _process(delta: float) -> void:
	_try_prediction_resync()
	if _blend_remaining > 0.0:
		var step := minf(delta, _blend_remaining)
		_blend_remaining -= step
		visual_layer.position.x = _blend_start_offset_x * (_blend_remaining / 0.1)
		if _blend_remaining <= 0.0:
			visual_layer.position.x = 0.0
	if _position_installed:
		local_label.position.x = character_root.position.x - local_label.size.x / 2.0
		var control: Dictionary = MmoClient.prediction_control_state()
		var predicted_motion := {"velocity_mm_s": roundi(character_root.velocity.x * 1000.0 / PIXELS_PER_METER),
			"facing": control.facing}
		_pose(sprite, predicted_motion)

func _integrate_control(control: Dictionary, delta: float) -> void:
	var target_speed := float(control.drive) * float(_movement.top_speed_mm_s) * PIXELS_PER_METER / 1000.0
	var force := float(_movement.drive_force_mN if control.drive != 0 else _movement.brake_force_mN)
	var acceleration := force * PIXELS_PER_METER / float(_movement.mass_g)
	character_root.velocity.x = move_toward(character_root.velocity.x, target_speed, acceleration * delta)
	character_root.velocity.y = 0.0
	character_root.move_and_slide()
	var contacts: Array[String] = []
	for index in range(character_root.get_slide_collision_count()):
		var collider: Object = character_root.get_slide_collision(index).get_collider()
		if collider is Node and collider.has_meta("contact_id"):
			var contact_id := str(collider.get_meta("contact_id"))
			if not contacts.has(contact_id): contacts.append(contact_id)
	var half_width_mm := int(_movement.width_mm / 2)
	var position_mm := _pixel_to_server_mm(character_root.position.x)
	var min_center := roundi(float(_map.min_x) * 1000.0 / float(_map.units_per_meter)) + half_width_mm
	var max_center := roundi(float(_map.max_x) * 1000.0 / float(_map.units_per_meter)) - half_width_mm
	if abs(position_mm - min_center) <= 2 and not contacts.has("wall_min"): contacts.append("wall_min")
	if abs(position_mm - max_center) <= 2 and not contacts.has("wall_max"): contacts.append("wall_max")
	contacts.sort()
	_predicted_contacts = contacts
	if contacts.has("wall_min") or contacts.has("wall_max"):
		character_root.velocity.x = 0.0

func _apply_authoritative_motion(motion: Dictionary, force_snap: bool) -> void:
	if character_root == null or _movement.is_empty(): return
	_prediction_metrics.last_simulation_tick = int(motion.get("simulation_tick", -1))
	var before_render_x := character_root.position.x + visual_layer.position.x
	var error_mm := abs(_pixel_to_server_mm(character_root.position.x) - int(motion.position_mm))
	if not force_snap:
		_prediction_metrics.samples += 1
		_prediction_metrics.max_divergence_mm = maxi(_prediction_metrics.max_divergence_mm, error_mm)
	var contact_disagreement := not force_snap and motion.contacts != _predicted_contacts
	var replay: Array[Dictionary] = []
	if not force_snap:
		for entry in _control_history:
			if int(entry.control_seq) > int(motion.last_applied_control_seq): replay.append(entry)
	_control_history = replay
	_last_applied_control_seq = int(motion.last_applied_control_seq)
	character_root.position.x = server_to_pixel(int(motion.position_mm))
	character_root.velocity = Vector2(float(motion.velocity_mm_s) * PIXELS_PER_METER / 1000.0, 0.0)
	_predicted_contacts.clear()
	for entry in _control_history:
		_integrate_control(entry, 1.0 / float(_movement.physics_hz))
	var can_blend := not force_snap and error_mm <= 250 and not contact_disagreement
	if can_blend:
		visual_layer.position.x = before_render_x - character_root.position.x
		_blend_start_offset_x = visual_layer.position.x
		_blend_remaining = 0.1
		_prediction_metrics.small_blends += 1
	else:
		visual_layer.position.x = 0.0
		_blend_start_offset_x = 0.0
		_blend_remaining = 0.0
		character_root.reset_physics_interpolation()
		if not force_snap: _prediction_metrics.snaps += 1

func _pixel_to_server_mm(pixel_x: float) -> int:
	return roundi((float(_map.min_x) / float(_map.units_per_meter) + (pixel_x - ORIGIN_X) / PIXELS_PER_METER) * 1000.0)

func _fence_prediction() -> void:
	if _prediction_fenced: return
	_prediction_fenced = true
	_control_history.clear()
	_pending_owner_motion.clear()
	_prediction_metrics.fences += 1
	if _resync_requested: return
	_resync_requested = true
	if MmoClient.state in ["READY", "MOVING"]:
		var control: Dictionary = MmoClient.prediction_control_state()
		if control.drive != 0: MmoClient.set_control(0, control.facing)
		_try_prediction_resync()

func _try_prediction_resync() -> void:
	if _resync_requested and MmoClient.state == "READY":
		MmoClient.request_state()

func _pose(target: AnimatedSprite2D, motion: Dictionary) -> void:
	var animation := ("walk_" if motion.velocity_mm_s != 0 else "idle_") + ("left" if motion.facing < 0 else "right")
	if _suspended: target.pause()
	else: target.play(animation)

func _remove_remote(id: String) -> void:
	var node: Node = remote_players[id]
	remote_players.erase(id)
	remove_child(node)
	node.queue_free()

func _sync_players() -> void:
	var players: Dictionary = _view.players
	var local_id: String = _view.local_player_id
	for id in remote_players.keys():
		if not players.has(id) or id == local_id: _remove_remote(id)
	for id in players:
		if id == local_id: continue
		if not remote_players.has(id):
			var node := RemotePlayer.new()
			node.player_id = id
			node.position.y = FLOOR_Y
			node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			add_child(node)
			remote_players[id] = node
		remote_players[id].suspended = _suspended
		remote_players[id].project(players[id], server_to_pixel(players[id].motion.position_mm))

func _reframe() -> void:
	var half_width := get_viewport_rect().size.x / 2.0
	var right := ORIGIN_X * 2.0 + world_length
	camera.position.x = right / 2.0 if right < half_width * 2.0 else clampf(character_root.position.x, half_width, right - half_width)
	_update_tiles()
	queue_redraw()
	ruler.queue_redraw()

func _resize_projection() -> void:
	_first_cell = -1000000
	if not _map.is_empty():
		project(_map, _view, _display_x)

func _update_tiles() -> void:
	# A bounded visible strip also handles legal maps far larger than tile limits.
	var left := camera.position.x - get_viewport_rect().size.x / 2.0
	var first := int(floor(left / TILE_SIZE)) - 1
	if first == _first_cell:
		return
	_first_cell = first
	terrain.clear()
	var count := int(ceil(get_viewport_rect().size.x / TILE_SIZE)) + 3
	for cell in range(first, first + count):
		var px := cell * TILE_SIZE
		if px + TILE_SIZE > ORIGIN_X and px < ORIGIN_X + world_length:
			# Use a local strip origin to avoid TileMapLayer's 16-bit cell coordinates.
			terrain.set_cell(Vector2i(cell - first, 0), 0, Vector2i(posmod(cell, 2), 0))
	terrain.position.x = first * TILE_SIZE

func _draw() -> void:
	if _map.is_empty():
		return
	var left := camera.position.x - get_viewport_rect().size.x / 2.0
	var width := get_viewport_rect().size.x
	draw_rect(Rect2(left, -16, width, 160), Color("182a38"))
	draw_rect(Rect2(left, 16, width, 88), Color("394e5b"))
	for panel in range(int(floor(left / 80.0)), int(ceil((left + width) / 80.0)) + 1):
		draw_rect(Rect2(panel * 80 + 8, 24, 60, 54), Color("496572"))
		draw_line(Vector2(panel * 80 + 8, 80), Vector2(panel * 80 + 68, 80), Color("203b49"), 2)
	draw_rect(Rect2(left, FLOOR_Y + 16, width, 40), Color("101f2b"))
	# Walls use exact min/max projection even when the last tile is partial.
	for boundary in [ORIGIN_X, ORIGIN_X + world_length]:
		draw_rect(Rect2(boundary - 3, 12, 6, FLOOR_Y - 12), Color("c2b799"))

func ruler_marks() -> Array[Dictionary]:
	# Visible ticks only. Dense unit scales use readable multiples, never huge loops.
	var marks: Array[Dictionary] = []
	if _map.is_empty():
		return marks
	var pixels_per_unit := PIXELS_PER_METER / float(_map.units_per_meter)
	var step := 1
	while float(step) * pixels_per_unit < 8.0:
		step *= 10
	for divisor in [5, 2]:
		if float(step / divisor) * pixels_per_unit >= 8.0:
			step = int(step / divisor)
	var major_step := step * 5
	var font := ThemeDB.fallback_font
	while font.get_string_size(str(_map.max_x), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 6 > float(major_step) * pixels_per_unit:
		major_step *= 2
	var left := camera.position.x - get_viewport_rect().size.x / 2.0
	var right := left + get_viewport_rect().size.x
	var low := maxi(_map.min_x, int(ceil(float(_map.min_x) + (left - ORIGIN_X) / pixels_per_unit)))
	var high := mini(_map.max_x, int(floor(float(_map.min_x) + (right - ORIGIN_X) / pixels_per_unit)))
	var first := int(ceil(float(low) / float(step))) * step
	for x in range(first, high + 1, step):
		marks.append({"x": x, "pixel": server_to_pixel(roundi(float(x) * 1000.0 / float(_map.units_per_meter))), "major": x % major_step == 0})
	return marks

func _draw_ruler() -> void:
	if _map.is_empty():
		return
	var left := camera.position.x - get_viewport_rect().size.x / 2.0
	var width := get_viewport_rect().size.x
	var low := maxf(left, ORIGIN_X)
	var high := minf(left + width, ORIGIN_X + world_length)
	var font := ThemeDB.fallback_font
	var confirmed := server_to_pixel(_view.confirmed_local_position_mm)
	var cell_width := PIXELS_PER_METER / float(_map.units_per_meter)
	var cell_left := maxf(ORIGIN_X, confirmed - cell_width / 2.0)
	var cell_right := minf(ORIGIN_X + world_length, confirmed + cell_width / 2.0)
	ruler.draw_rect(Rect2(low, FLOOR_Y, high - low, 12), Color("172c39"))
	ruler.draw_rect(Rect2(cell_left, FLOOR_Y, cell_right - cell_left, 12), Color("b58a35"))
	ruler.draw_line(Vector2(low, FLOOR_Y), Vector2(high, FLOOR_Y), Color("9cb7c5"))
	var caption := "%.3f m" % (float(_view.confirmed_local_position_mm) / 1000.0)
	var caption_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 6
	var caption_left := clampf(confirmed - caption_width / 2.0, left + 2, left + width - caption_width - 2)
	# Exact confirmed coordinate, distinct from the interpolated/predicted body.
	for mark in ruler_marks():
		ruler.draw_line(Vector2(mark.pixel, FLOOR_Y), Vector2(mark.pixel, FLOOR_Y + (4 if mark.major else 2)), Color("c2d2d9"))
		if mark.major and absf(mark.pixel - confirmed) > caption_width / 2.0 + 10:
			var text := str(mark.x)
			var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			ruler.draw_string(font, Vector2(mark.pixel - text_width / 2.0, FLOOR_Y + 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("d0dce2"))
	ruler.draw_rect(Rect2(caption_left, FLOOR_Y + 2, caption_width, 10), Color("5c441d"))
	ruler.draw_string(font, Vector2(caption_left + 3, FLOOR_Y + 11), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("ffe5a0"))
	ruler.draw_line(Vector2(confirmed, FLOOR_Y - 3), Vector2(confirmed, FLOOR_Y + 1), Color("ffe5a0"), 2)
