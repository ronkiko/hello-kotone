extends Node2D
## Confirmed replica projection plus owner-only prediction; server remains authority.
const Protocol = preload("res://scripts/mmo/protocol_v8.gd")
const RemotePlayer = preload("res://scripts/presentation/remote_player.gd")
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const GaitAnimator = preload("res://scripts/presentation/gait_animator.gd")
const CharacterCollider = preload("res://scripts/presentation/character_collider.gd")
const TERRAIN = preload("res://assets/mmo/platform.svg")
const PIXELS_PER_METER := 8.0
const ORIGIN_X := 32.0
const FLOOR_Y := 104.0
const TILE_SIZE := 16
const NUMERICAL_PRESENTATION_PX := 0.05
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
var _peer_proxies: Dictionary = {}
var _peer_lead_ticks := 0
var _peer_anchor_ordinal := 0
var world_length := 0.0
var _map: Dictionary = {}
var _view: Dictionary = {}
var _display_x: Variant = null
var _movement: Dictionary = {}
var _position_installed := false
var _first_cell := -1000000
var _bound_nodes: Array[StaticBody2D] = []
var _local_player_id := ""
var _owner_scope := ""
var _last_applied_control_seq := 0
var _prediction_ordinal := -1
var _control_ledger: Dictionary = {}
var _local_control: Dictionary = {}
var _local_control_start := 0
var _gait_displacement := 0.0
var _correction_class := "none"
var _diagnostic_motion: Dictionary = {}
var _last_authoritative_tick := -1
var _prediction_history: Array[Dictionary] = []
var _pending_owner_motion: Dictionary = {}
var _pending_snapshot_motion: Dictionary = {}
var _prediction_fenced := false
var _resync_requested := false
var _predicted_contacts: Array[String] = []
var _blend_remaining := 0.0
var _blend_start_offset_x := 0.0
var _prediction_metrics := {"samples": 0, "max_divergence_mm": 0, "last_simulation_tick": -1,
	"small_blends": 0, "snaps": 0, "history_peak": 0, "fences": 0,
	"last_replayed_ticks": 0, "last_applied_control_seq": 0}
var _gait := GaitAnimator.new()
var _local_model_id := ""

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
	character_root.collision_mask = 5
	character_collision.disabled = true
	character_root.add_child(character_collision)
	add_child(character_root)
	visual_layer.name = "CharacterVisualLayer"
	visual_layer.scale = Vector2.ONE * Appearance.DISPLAY_SCALE
	visual_layer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
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
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	camera.position.y = 58.0
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()
	get_viewport().size_changed.connect(_resize_projection)
	MmoClient.control_sent.connect(_record_sent_control)
	MmoClient.input_rejected.connect(_discard_rejected_control)
	MmoClient.world_replica.motion_received.connect(_queue_owner_motion)
	MmoClient.world_replica.authoritative_snapshot_received.connect(_queue_snapshot_motion)
	project(_map, _view, _display_x)

func set_movement_rules(rules: Dictionary) -> bool:
	if not Protocol.movement(rules.get("movement")): return false
	_movement = rules.movement.duplicate(true)
	return true

func server_to_pixel(position_mm: float) -> float:
	return ORIGIN_X + (float(position_mm) / 1000.0 - float(_map.min_x) / float(_map.units_per_meter)) * PIXELS_PER_METER

func project(document: Dictionary, view: Dictionary, _unused: Variant = null) -> bool:
	if _movement.is_empty() or not Protocol.map_definition(document) or not Protocol.map_reference(view.get("map")): return false
	for key in ["map_id", "content_version", "content_hash"]:
		if document[key] != view.map[key]: return false
	var players: Variant = view.get("players", {})
	if not players is Dictionary or not players.has(view.get("local_player_id")) or players.size() > 64: return false
	for id in players:
		if not Protocol.player(players[id]) or players[id].player_id != id or players[id].zone_id != document.map_id \
			or Protocol.selected_physics(_movement, players[id]).is_empty(): return false
	var map_changed: bool = _map.get("map_id", "") != document.map_id or _map.get("content_hash", "") != document.content_hash
	_map = document.duplicate(true)
	_view = view.duplicate(true)
	if map_changed:
		_install_world_bounds()
	world_length = float(document.max_x - document.min_x) / float(document.units_per_meter) * PIXELS_PER_METER
	var local: Dictionary = players[view.local_player_id]
	var local_physics := Protocol.selected_physics(_movement, local)
	_movement.merge(local_physics.body, true)
	_movement.merge(local_physics.motor, true)
	if not is_node_ready(): return true
	_configure_owner_shape()
	var owner_scope := "%s|%s|%d" % [str(view.get("epoch","")),str(view.map.map_id),int(view.get("zone_generation",1))]
	if not _position_installed or _local_player_id != view.local_player_id or owner_scope != _owner_scope:
		_owner_scope = owner_scope
		_clear_peer_proxies()
		_local_player_id = view.local_player_id
		_position_installed = true
		_prediction_fenced = false
		_prediction_history.clear()
		var initial_motion: Dictionary = local.motion.duplicate(true)
		initial_motion["contacts"] = local.contacts.duplicate()
		_apply_authoritative_motion(initial_motion, true)
	local_label.position.x = character_root.position.x - 64
	local_label.text = "%s (you)" % local.nickname
	Appearance.install(sprite, local.character.appearance_payload)
	if _local_model_id != local.character.appearance_payload.character_model_id:
		_local_model_id = local.character.appearance_payload.character_model_id
		_gait.reset(sprite, int(local.motion.facing))
	_gait.configure(float(_movement.top_speed_mm_s) * PIXELS_PER_METER / 1000.0)
	local_label.position.y = FLOOR_Y - Appearance.display_height_px(local.character.appearance_payload.character_model_id) - 18
	_sync_players()
	_reframe()
	return true

func set_suspended(value: bool) -> void:
	_suspended = value
	if value:
		_clear_peer_proxies()
		_pending_owner_motion.clear()
		_pending_snapshot_motion.clear()
		_prediction_history.clear()
		_prediction_ordinal = -1
		_control_ledger.clear()
		_local_control.clear()
		_last_authoritative_tick = -1
		_blend_remaining = 0.0
		_blend_start_offset_x = 0.0
		visual_layer.position.x = 0.0
		_gait.reset(sprite, int(MmoClient.prediction_control_state().facing))
	if sprite != null and value: sprite.pause()
	for node in remote_players.values():
		node.set_suspended(value)

func prediction_metrics() -> Dictionary:
	return _prediction_metrics.duplicate(true)

func prediction_diagnostics() -> Dictionary:
	# Caller-owned bounded evidence; no trace/log accumulation or session secrets.
	return {"sample":_diagnostic_motion.duplicate(true),"ledger":_control_ledger.duplicate(true),"local_usec":Time.get_ticks_usec(),"local_ordinal":_prediction_ordinal,
		"simulation_tick":_last_authoritative_tick,"applied_seq":_last_applied_control_seq,
		"desired":MmoClient.prediction_control_state(),"acknowledged":MmoClient._server_input.duplicate(),
		"body_mm":_pixel_to_server_mm(character_root.position.x),
		"render_mm":_pixel_to_server_mm(character_root.position.x+visual_layer.position.x),
		"offset_px":visual_layer.position.x,"predicted_contacts":_predicted_contacts.duplicate(),
		"correction_class":_correction_class,"animation":String(sprite.animation),
		"gait_walking":_gait.walking,"camera_px":camera.position.x}

func _configure_owner_shape() -> void:
	if _movement.is_empty(): return
	CharacterCollider.install(character_collision, _movement, PIXELS_PER_METER)

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
	if _prediction_ordinal < 0: return
	var control: Dictionary = MmoClient.prediction_control_state()
	var too_old := not _prediction_history.is_empty() and Time.get_ticks_msec() - int(_prediction_history[0].at_ms) > 2000
	if _prediction_history.size() >= 40 or too_old:
		_fence_prediction()
		return
	_track_local_control(control)
	# This ordinal belongs only to the local Godot clock.
	_prediction_ordinal += 1
	_update_peer_proxies(float(_peer_lead_ticks + _prediction_ordinal - _peer_anchor_ordinal))
	var before_step := character_root.position.x
	_integrate_control(control, delta)
	_gait_displacement += character_root.position.x - before_step
	_prediction_history.append({"local_ordinal": _prediction_ordinal,
		"drive": control.drive, "facing": control.facing, "at_ms": Time.get_ticks_msec(),
		"position_mm": _pixel_to_server_mm(character_root.position.x),
		"contacts": _predicted_contacts.duplicate()})
	_prediction_metrics.history_peak = maxi(_prediction_metrics.history_peak, _prediction_history.size())
	if _blend_remaining <= 0.0 and absf(visual_layer.position.x) > NUMERICAL_PRESENTATION_PX \
		and absf(character_root.velocity.x) > 0.0001:
		_blend_remaining = delta
		_blend_start_offset_x = visual_layer.position.x*(0.1/delta)
	if _blend_remaining > 0.0 and absf(character_root.velocity.x) < 0.0001 \
		and absf(visual_layer.position.x) <= NUMERICAL_PRESENTATION_PX:
		# Numerical rest residue is bounded; do not manufacture a reverse stop step.
		_blend_remaining = 0.0
		_correction_class = "none"
	if _blend_remaining > 0.0:
		var step := minf(delta, _blend_remaining)
		_blend_remaining -= step
		var target_offset := _blend_start_offset_x * (_blend_remaining / 0.1)
		var offset_delta := target_offset-visual_layer.position.x
		var integrated_delta := character_root.position.x-before_step
		if absf(integrated_delta) <= 0.000001:
			# A stopped authoritative body has no same-direction displacement budget.
			# Hold the presentation residue until later motion can absorb it instead
			# of manufacturing a visible/logical reverse step at rest.
			offset_delta = 0.0
		elif offset_delta*integrated_delta < 0.0:
			# Convergence cannot cancel more than this interval's forward motion.
			offset_delta = signf(offset_delta)*minf(absf(offset_delta),absf(integrated_delta))
		visual_layer.position.x += offset_delta
		if _blend_remaining > 0.000001:
			_blend_start_offset_x = visual_layer.position.x*(0.1/_blend_remaining)
		elif absf(visual_layer.position.x) > NUMERICAL_PRESENTATION_PX:
			_blend_remaining = delta
			_blend_start_offset_x = visual_layer.position.x*(0.1/_blend_remaining)
		else:
			_blend_remaining = 0.0
	_reframe()

func _process(delta: float) -> void:
	_try_prediction_resync()
	if _position_installed:
		local_label.position.x = character_root.position.x + visual_layer.position.x - local_label.size.x / 2.0
		var control: Dictionary = MmoClient.prediction_control_state()
		var predicted_motion := {"velocity_mm_s": roundi(character_root.velocity.x * 1000.0 / PIXELS_PER_METER),
			"facing": control.facing}
		if _suspended: sprite.pause()
		else: _gait.update(sprite, 0.0, _gait_displacement, int(predicted_motion.facing), delta)
		_gait_displacement = 0.0
		_reframe()
	var now_usec := Time.get_ticks_usec()
	for node in remote_players.values():
		if node.suspended: continue
		var remote_motion: Dictionary = node.timeline.sample_at(now_usec)
		if not remote_motion.is_empty():
			node.render_at(server_to_pixel(float(remote_motion.position_mm)), remote_motion, delta)

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
	var half_width_mm := int(_movement.collision_width_mm / 2)
	var position_mm := _pixel_to_server_mm(character_root.position.x)
	var min_center := roundi(float(_map.min_x) * 1000.0 / float(_map.units_per_meter)) + half_width_mm
	var max_center := roundi(float(_map.max_x) * 1000.0 / float(_map.units_per_meter)) - half_width_mm
	if abs(position_mm - min_center) <= 2 and not contacts.has("wall_min"): contacts.append("wall_min")
	if abs(position_mm - max_center) <= 2 and not contacts.has("wall_max"): contacts.append("wall_max")
	contacts.sort()
	_predicted_contacts = contacts
	if contacts.has("wall_min") or contacts.has("wall_max"):
		character_root.velocity.x = 0.0

func _track_local_control(control: Dictionary) -> void:
	var semantics := {"drive":control.drive,"facing":control.facing}
	if semantics != _local_control:
		_local_control = semantics
		_local_control_start = _prediction_ordinal + 1

func _record_sent_control(control: Dictionary) -> void:
	if _suspended or _prediction_fenced or _prediction_ordinal < 0: return
	_track_local_control(control)
	_control_ledger[int(control.control_seq)] = {"first_ordinal":_local_control_start,"control":_local_control.duplicate()}
	if _control_ledger.size() > 40: _fence_prediction()

func _discard_rejected_control(_code: String) -> void:
	# A definite rejection cannot become a future applied-boundary mapping.
	_control_ledger.erase(int(MmoClient._server_input_seq)+1)

func _apply_authoritative_motion(motion: Dictionary, force_snap: bool) -> void:
	if character_root == null or _movement.is_empty(): return
	var tick := int(motion.simulation_tick)
	var applied_seq := int(motion.last_applied_control_seq)
	if not force_snap and (tick < _last_authoritative_tick or applied_seq < _last_applied_control_seq):
		_fence_prediction()
		return
	_diagnostic_motion = motion.duplicate(true)
	_prediction_metrics.last_simulation_tick = tick
	_last_authoritative_tick = tick
	_last_applied_control_seq = applied_seq
	_prediction_metrics.last_applied_control_seq = applied_seq
	_gait.try_contact_reaction(sprite, _local_model_id, motion)
	var mapped_ordinal := 0
	if force_snap:
		_prediction_ordinal = 0
		_prediction_history.clear()
		_control_ledger.clear()
		_local_control.clear()
		_control_ledger[applied_seq] = {"first_ordinal":0,"lead_ticks":0,"control":{"drive":0,"facing":motion.facing}}
		_gait_displacement = 0.0
	else:
		if not _control_ledger.has(applied_seq):
			_fence_prediction()
			return
		_track_local_control(MmoClient.prediction_control_state())
		var boundary: Dictionary = _control_ledger[applied_seq]
		if not boundary.has("lead_ticks"):
			# The first applied boundary measures prediction lead for this control.
			# Retaining it prevents server overruns from becoming ever-growing replay.
			mapped_ordinal = int(boundary.first_ordinal) + tick - int(motion.control_started_tick)
			boundary.lead_ticks = maxi(0,_prediction_ordinal-mapped_ordinal)
		else:
			mapped_ordinal = _prediction_ordinal-int(boundary.lead_ticks)
			# If no local interval occurred, real authoritative progress can retire
			# the remaining history. A server origin is never a local clock index.
			if boundary.has("last_receive_ordinal") and _prediction_ordinal==int(boundary.last_receive_ordinal):
				mapped_ordinal = maxi(mapped_ordinal,int(boundary.last_mapped_ordinal)+tick-int(boundary.last_sample_tick))
		mapped_ordinal = mini(_prediction_ordinal,mapped_ordinal)
		boundary.last_receive_ordinal = _prediction_ordinal
		boundary.last_sample_tick = tick
		boundary.last_mapped_ordinal = mapped_ordinal
		if boundary.control != _local_control and mapped_ordinal >= _local_control_start and motion.contacts.is_empty():
			_correction_class = "pending_control"
			return
		for seq in _control_ledger:
			if int(seq) > applied_seq and mapped_ordinal >= int(_control_ledger[seq].first_ordinal) \
				and motion.contacts.is_empty():
				# An old held-control sample cannot confirm the predicted release.
				# Wait for its applied boundary; peer/wall authority never waits.
				_correction_class = "pending_control"
				return
	var before_body_x := character_root.position.x
	var before_render_x := character_root.position.x + visual_layer.position.x
	var replay: Array[Dictionary] = []
	if not force_snap:
		for entry in _prediction_history:
			if int(entry.local_ordinal) > mapped_ordinal: replay.append(entry)
	_prediction_history = replay
	for seq in _control_ledger.keys():
		if int(seq) < applied_seq: _control_ledger.erase(seq)
	_prediction_metrics.last_replayed_ticks = replay.size()
	_peer_lead_ticks = replay.size()
	_peer_anchor_ordinal = _prediction_ordinal
	character_root.position.x = server_to_pixel(int(motion.position_mm))
	character_root.velocity = Vector2(float(motion.velocity_mm_s) * PIXELS_PER_METER / 1000.0, 0.0)
	_predicted_contacts.assign(motion.contacts)
	var replay_index := 0
	for entry in replay:
		replay_index += 1
		_update_peer_proxies(float(replay_index))
		_integrate_control(entry, 1.0 / float(_movement.physics_hz))
		entry.position_mm = _pixel_to_server_mm(character_root.position.x)
		entry.contacts = _predicted_contacts.duplicate()
	var error_mm := absi(_pixel_to_server_mm(before_body_x) - _pixel_to_server_mm(character_root.position.x))
	if not force_snap:
		_prediction_metrics.samples += 1
		_prediction_metrics.max_divergence_mm = maxi(_prediction_metrics.max_divergence_mm, error_mm)
	# A control-boundary phase change can cover up to one 100-ms travel window.
	# Its distance depends on the installed motor, not a shared character speed.
	var blend_budget_mm := maxf(250.0, float(_movement.top_speed_mm_s) * 0.1)
	# Sub-mm native/integer quantization is not a new 100-ms blend every frame.
	# Keep a tiny visual residue, clear it once the authority is settled.
	if not force_snap and error_mm <= 2:
		visual_layer.position.x = before_render_x - character_root.position.x
		# Preserve an in-progress convergence deadline across numerical samples.
		# Canceling its timer here used to strand an offset until a stop snap.
		if _blend_remaining > 0.0:
			_blend_start_offset_x = visual_layer.position.x * (0.1 / _blend_remaining)
		_correction_class = "blend" if _blend_remaining > 0.0 else "none"
	elif not force_snap and error_mm <= blend_budget_mm and motion.contacts.is_empty():
		visual_layer.position.x = before_render_x - character_root.position.x
		_blend_start_offset_x = visual_layer.position.x
		_blend_remaining = 0.1
		_correction_class = "blend"
		_prediction_metrics.small_blends += 1
	else:
		visual_layer.position.x = 0.0
		_blend_remaining = 0.0
		character_root.reset_physics_interpolation()
		_correction_class = "snap"
		if not force_snap: _prediction_metrics.snaps += 1

func _pixel_to_server_mm(pixel_x: float) -> int:
	return roundi((float(_map.min_x) / float(_map.units_per_meter) + (pixel_x - ORIGIN_X) / PIXELS_PER_METER) * 1000.0)

func _fence_prediction() -> void:
	if _prediction_fenced: return
	_prediction_fenced = true
	_prediction_history.clear()
	_control_ledger.clear()
	_local_control.clear()
	_prediction_ordinal = -1
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

func _remove_remote(id: String) -> void:
	var node: Node = remote_players[id]
	remote_players.erase(id)
	if _peer_proxies.has(id):
		var proxy: Node = _peer_proxies[id]
		_peer_proxies.erase(id)
		remove_child(proxy)
		proxy.queue_free()
	remove_child(node)
	node.queue_free()

func _sync_players() -> void:
	var players: Dictionary = _view.players
	var local_id: String = _view.local_player_id
	var scope := "%s|%s|%d" % [str(_view.get("epoch", "")), str(_view.map.get("map_id", "")), int(_view.get("zone_generation", 1))]
	var received_usec := Time.get_ticks_usec()
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
		var latest_frame_sample: Dictionary = MmoClient.world_replica.latest_frame_sample(id)
		remote_players[id].project(players[id], server_to_pixel(float(players[id].motion.position_mm)),
			scope, received_usec, int(Protocol.selected_physics(_movement, players[id]).motor.top_speed_mm_s), latest_frame_sample)

func _clear_peer_proxies() -> void:
	for proxy in _peer_proxies.values():
		remove_child(proxy)
		proxy.queue_free()
	_peer_proxies.clear()

func _update_peer_proxies(lead_ticks: float) -> void:
	for id in remote_players:
		var hint: Dictionary = remote_players[id].timeline.prediction_hint(Time.get_ticks_usec(), lead_ticks)
		if hint.is_empty() or _suspended:
			if _peer_proxies.has(id): _peer_proxies[id].collision_layer = 0
			continue
		if not _peer_proxies.has(id):
			var proxy := StaticBody2D.new()
			proxy.name = "PredictionPeer_" + id
			proxy.collision_mask = 0
			proxy.set_meta("contact_id", id)
			var collision := CollisionShape2D.new()
			var body: Dictionary = Protocol.selected_physics(_movement, _view.players[id]).body
			CharacterCollider.install(collision, body, PIXELS_PER_METER)
			proxy.add_child(collision)
			add_child(proxy)
			_peer_proxies[id] = proxy
		var proxy: StaticBody2D = _peer_proxies[id]
		proxy.collision_layer = 4
		proxy.position = Vector2(server_to_pixel(float(hint.position_mm)), FLOOR_Y)
		proxy.constant_linear_velocity = Vector2(float(hint.velocity_mm_s)*PIXELS_PER_METER/1000.0,0)

func _reframe() -> void:
	var half_width := get_viewport_rect().size.x / 2.0
	var right := ORIGIN_X * 2.0 + world_length
	camera.position.x = right / 2.0 if right < half_width * 2.0 else clampf(character_root.position.x + visual_layer.position.x, half_width, right - half_width)
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
