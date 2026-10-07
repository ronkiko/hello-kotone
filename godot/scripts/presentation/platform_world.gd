extends Node2D
## Read-only projection. Replica facts plus an optional bounded display target.
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
var character_root := Node2D.new()
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
	add_child(character_root)
	visual_layer.name = "CharacterVisualLayer"
	visual_layer.scale = Vector2.ONE * Appearance.DISPLAY_SCALE
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
	project(_map, _view, _display_x)

func set_movement_rules(rules: Dictionary) -> bool:
	if not Protocol.movement(rules.get("movement")): return false
	_movement = rules.movement.duplicate(true)
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
	_map = document.duplicate(true)
	_view = view.duplicate(true)
	world_length = float(document.max_x - document.min_x) / float(document.units_per_meter) * PIXELS_PER_METER
	if not is_node_ready(): return true
	var local: Dictionary = players[view.local_player_id]
	character_root.position.x = server_to_pixel(local.motion.position_mm)
	local_label.position.x = character_root.position.x - 64
	local_label.text = "%s (you)" % local.nickname
	Appearance.install(sprite, local.character.appearance_payload)
	local_label.position.y = FLOOR_Y - Appearance.display_height_px(local.character.appearance_payload.character_model_id) - 18
	_pose(sprite, local.motion)
	_sync_players()
	_reframe()
	return true

func set_suspended(value: bool) -> void:
	_suspended = value
	if sprite != null and value: sprite.pause()
	for node in remote_players.values():
		if value: node.sprite.pause()

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
