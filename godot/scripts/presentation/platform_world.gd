extends Node2D
## Read-only projection. Receives verified map + replica view; no network/input.
const Protocol = preload("res://scripts/mmo/protocol_v4.gd")
const Kotone = preload("res://scenes/kotone.tscn")
const TERRAIN = preload("res://assets/mmo/platform.svg")
const PIXELS_PER_METER := 8.0
const ORIGIN_X := 32.0
const FLOOR_Y := 104.0
const TILE_SIZE := 16
var terrain := TileMapLayer.new()
var camera := Camera2D.new()
var sprite: Sprite2D
var world_length := 0.0
var _map: Dictionary = {}
var _view: Dictionary = {}
var _elapsed := 0.0
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
	sprite = Kotone.instantiate()
	# The standalone prototype controller owns local movement; MMO does not use it.
	sprite.set_script(null)
	sprite.scale = Vector2(0.65, 0.65)
	sprite.position.y = FLOOR_Y - 42.25
	add_child(sprite)
	camera.position.y = 58.0
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()
	get_viewport().size_changed.connect(_resize_projection)
	project(_map, _view)

func server_to_pixel(x: int) -> float:
	return ORIGIN_X + float(x - int(_map.min_x)) / float(_map.units_per_meter) * PIXELS_PER_METER

func project(document: Dictionary, view: Dictionary) -> bool:
	if not Protocol.map_definition(document) or not Protocol.map_reference(view.get("map")):
		return false
	for key in ["map_id", "content_version", "content_hash"]:
		if document[key] != view.map[key]:
			return false
	var x: Variant = view.get("confirmed_local_x")
	if not Protocol.integer(x, document.min_x, document.max_x):
		return false
	_map = document.duplicate(true)
	_view = view.duplicate(true)
	world_length = float(document.max_x - document.min_x) / float(document.units_per_meter) * PIXELS_PER_METER
	if not is_node_ready():
		return true
	sprite.position.x = server_to_pixel(x)
	var half_width := get_viewport_rect().size.x / 2.0
	var right := ORIGIN_X * 2.0 + world_length
	camera.position.x = right / 2.0 if right < half_width * 2.0 else clampf(sprite.position.x, half_width, right - half_width)
	_first_cell = -1000000
	_update_tiles()
	queue_redraw()
	return true

func _resize_projection() -> void:
	if not _map.is_empty():
		project(_map, _view)

func _process(delta: float) -> void:
	if _map.is_empty() or sprite == null:
		return
	_elapsed += delta
	sprite.frame = int(_elapsed / 0.3) % sprite.hframes

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
