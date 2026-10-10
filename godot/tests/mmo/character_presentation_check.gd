extends SceneTree
## Actual shared Creator/own/remote package, root and gait invariants.
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const Gait = preload("res://scripts/presentation/gait_animator.gd")
const FLOOR_Y := 104.0
var checks := 0
var failures := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	run.call_deferred()
func payload(model: String) -> Dictionary:
	return {"character_model_id":model,"body_variant_id":"standard","face_style_id":"soft","hair_style_id":"short" if model == "kotone" else "bob","hair_color_id":"chestnut" if model == "kotone" else "rose"}
func run() -> void:
	var shell: Node = load("res://scenes/mmo/login.tscn").instantiate()
	root.add_child(shell)
	# This SceneTree script starts before project autoload types are available to
	# preload. Load the production presenter after the real startup scene exists.
	var platform_script: GDScript = load("res://scripts/presentation/platform_world.gd")
	var platform: Node2D = platform_script.new()
	root.add_child(platform)
	platform.set_process(false)
	var document := {"schema_version":1,"map_id":"city/apartment","content_version":1,"min_x":0,"max_x":100,"spawn_x":50,"units_per_meter":1,"content_hash":"4f465435cbb8eb3e5154a4776be29e7aee4f73376e00fb26299bfbf0cfcd361b"}
	platform.set_movement_rules({"movement":preload("res://tests/mmo/replica_check.gd").rules()})
	var view := {"map":{"map_id":document.map_id,"content_version":1,"content_hash":document.content_hash},"confirmed_local_position_mm":50000,"epoch":"e1","local_player_id":"p1","players":{}}
	for model in ["kotone", "yuna"]:
		var definition := {"game_card_id":"hello-kotone","realm_id":"local","character_id":"p1","display_name":"local","appearance_schema_version":2,"appearance_payload":payload(model)}
		# Current Protocol.character includes the durable definition shape used by v7.
		var player := {"player_id":"p1","nickname":"local","zone_id":"city/apartment","motion":{"position_mm":50000,"velocity_mm_s":0,"facing":1,"last_applied_control_seq":0,"control_started_tick":0,"simulation_tick":0},"contacts":[],"character":definition,"physics":preload("res://tests/mmo/replica_check.gd").binding(model)}
		var remote := player.duplicate(true)
		remote.player_id = "p2"
		remote.character.character_id = "p2"
		remote.character.display_name = "remote"
		remote.nickname = "remote"
		view.players = {"p1":player,"p2":remote}
		check(platform.project(document,view), model + " current character projection")
		if not platform.remote_players.has("p2"): continue
		var physical := preload("res://tests/mmo/replica_check.gd").physics(model)
		check(platform._movement.mass_g == physical.body.mass_g and platform._movement.top_speed_mm_s == physical.motor.top_speed_mm_s, model + " predictor uses selected server profile")
		check(is_equal_approx(platform.character_collision.shape.size.x, physical.body.collision_width_mm * 8.0/1000.0), model + " native owner width from body")
		var collider_size: Vector2 = platform.character_collision.shape.size
		var collider_offset: Vector2 = platform.character_collision.position
		var bad_view := view.duplicate(true)
		bad_view.players.p1.physics.motor_profile_id = "missing"
		check(not platform.project(document,bad_view), model + " unknown actuator binding fails closed")
		shell._preview(payload(model))
		var own: AnimatedSprite2D = platform.sprite
		var other: AnimatedSprite2D = platform.remote_players.p2.sprite
		check(shell.preview.sprite_frames == own.sprite_frames and other.sprite_frames == own.sprite_frames, model + " Creator own remote same resource")
		check(own.scale == Vector2.ONE and own.position == Vector2(-128,-236), model + " canonical visual transform")
		check(shell.preview.get_parent().scale == own.get_parent().scale and other.get_parent().scale == own.get_parent().scale, model + " common display transform")
		var expected_height := Appearance.display_height_px(model)
		check(is_equal_approx(platform.local_label.position.y, FLOOR_Y - expected_height - 18), model + " local label follows metric height")
		check(is_equal_approx(platform.remote_players.p2.identity.position.y, -expected_height - 18), model + " remote label follows metric height")
		if model == "yuna":
			var remote_node: Node = platform.remote_players.p2
			var physical_response := {"contact_delta_velocity_mm_s":8400,"contact_response_tick":12,"contact_response_facing":1,
				"contact_response_contacts":["p1"],"contact_shove_sources":["p1"]}
			check(remote_node.gait.try_contact_reaction(other,"yuna",physical_response), "remote starts received mass-aware reaction")
			var contact_player := remote.duplicate(true)
			contact_player.motion.simulation_tick = 15
			contact_player.contacts = ["p1"]
			remote_node.project(contact_player,remote_node.position.x,"e1|city/apartment|1",50000,4200)
			check(remote_node.gait.last_contact_response_tick == 12 and other.animation == Gait.PUSH_REACTION, "position rebase preserves consumed event and playing reaction")
			check(not remote_node.gait.try_contact_reaction(other,"yuna",physical_response), "contact rebase does not replay consumed event")
			remote_node.set_suspended(true)
			check(remote_node.gait.last_contact_response_tick == 0 and remote_node.timeline._responses.is_empty(), "visit suspension clears causal response scope")
			remote_node.set_suspended(false)
		var position: Vector2 = platform.character_root.position
		var gait := Gait.new()
		gait.configure(24)
		for facing in [-1,1]:
			for index in range(own.sprite_frames.get_frame_count(Appearance.walk_animation(facing))):
				Appearance.pose(own,true,facing,index)
				check(own.position == Vector2(-128,-236) and own.scale == Vector2.ONE and platform.character_root.position == position, model + " walk frame preserves anchor")
		gait.reset(own, 1)
		gait.update(own,0,3,-1,.1)
		check(own.animation == Appearance.walk_animation(-1) and platform.character_root.position == position, model + " rendered motion selects walk without relying on held input")
		gait.update(own,3,3,1,.1)
		check(own.animation == Appearance.idle_animation(1) and not own.is_playing(), model + " stationary authoritative facing selects calm idle without phantom movement")
		gait.update(own,3,6,1,.1)
		check(own.animation == Appearance.walk_animation(1), model + " external displacement advances gait without input state")
		for direction in [-1, 1]:
			gait.reset(own, direction)
			gait.update(own, 0, 0, direction, .1)
			check(own.animation == Appearance.idle_animation(direction) and gait.facing == direction, model + " stationary server-facing update selects authored idle")
			check(not own.flip_h and not own.flip_v, model + " directional idle uses prepared textures without mirroring")
			for index in range(own.sprite_frames.get_frame_count(Appearance.idle_animation(direction))):
				Appearance.pose(own, false, direction, index)
				check(own.position == Vector2(-128,-236) and own.scale == Vector2.ONE and platform.character_root.position == position, model + " directional idle preserves anchor")
			var remote_gait := Gait.new()
			remote_gait.reset(other, direction)
			remote_gait.update(other, 0, direction * 3, direction, .1)
			check(other.animation == Appearance.walk_animation(direction), model + " remote rendered displacement selects server-facing walk")
			remote_gait.update(other, direction * 3, direction * 3, direction, .1)
			check(other.animation == Appearance.idle_animation(direction) and remote_gait.facing == direction and not other.flip_h, model + " remote arrival settles into authoritative directional idle")
		var push_gait := Gait.new()
		push_gait.reset(own, 1)
		var push := {"contact_delta_velocity_mm_s":900,"contact_response_facing":1,
			"contact_response_tick":7,"contact_response_contacts":["p2"],"contact_shove_sources":["p2"]}
		var reaction_started: bool = push_gait.try_contact_reaction(own, model, push)
		if model == "yuna":
			check(reaction_started and own.animation == &"stumble_right2" and own.is_playing(), model + " server contact response selects authored Yuna reaction")
			push_gait.update(own, 0, 4, 1, .1)
			check(own.animation == &"stumble_right2", model + " reaction holds over gait until SpriteFrames completes it")
			own.set_frame_and_progress(4, 0.5)
			var second_push := {"contact_delta_velocity_mm_s":6000,"contact_response_facing":1,
				"contact_response_tick":8,"contact_response_contacts":["p2"],"contact_shove_sources":["p2"]}
			check(push_gait.try_contact_reaction(own, model, second_push)
				and own.animation == &"stumble_right2" and own.frame == 0
				and push_gait.last_contact_response_tick == 8,
				model + " later authoritative knockback restarts reaction from frame zero")
			check(not push_gait.try_contact_reaction(own, model, second_push),
				model + " duplicate response tick cannot restart reaction twice")
			var opposite_push := {"contact_delta_velocity_mm_s":-8400,"contact_response_facing":1,
				"contact_response_tick":9,"contact_response_contacts":["p2"],"contact_shove_sources":["p2"]}
			check(not push_gait.try_contact_reaction(own, model, opposite_push),
				model + " opposite-sign response is not the authored rightward stumble reaction")
			check(push_gait.last_contact_response_tick == 8,
				model + " rejected opposite-sign response cannot consume its causal tick")
			var pusher_slowdown := {"contact_delta_velocity_mm_s":900,"contact_response_facing":1,
				"contact_response_tick":10,"contact_response_contacts":["p2"],"contact_shove_sources":[]}
			check(not push_gait.try_contact_reaction(own, model, pusher_slowdown),
				model + " generic pusher contact slowdown is not a received shove reaction")
			check(push_gait.last_contact_response_tick == 8,
				model + " non-shove contact response cannot consume Yuna reaction tick")
		else:
			check(not reaction_started, model + " has no Yuna-only contact reaction")
		check(platform.character_collision.shape.size == collider_size
			and platform.character_collision.position == collider_offset,
			model + " walk idle and contact reaction never mutate physical collider")
	# Direct helpers are total on malformed resources; package loading rejects them.
	var malformed := AnimatedSprite2D.new()
	malformed.sprite_frames = SpriteFrames.new()
	Appearance.pose(malformed, false, -1, 7)
	check(Appearance.idle_frame(malformed, 1.0, -1) == 0 and Appearance.walk_frame_count(malformed, -1) == 0, "directional helpers safely reject missing animation data")
	malformed.free()
	# Independent, asymmetric resources prove direction selection never synthesizes pixels.
	var distinct := SpriteFrames.new()
	distinct.remove_animation(&"default")
	for direction in [-1, 1]:
		var animation := Appearance.idle_animation(direction)
		distinct.add_animation(animation)
		distinct.set_animation_speed(animation, 1)
		var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		image.fill(Color.RED if direction < 0 else Color.BLUE)
		var texture := ImageTexture.create_from_image(image)
		distinct.add_frame(animation, texture)
		if direction < 0: distinct.add_frame(animation, texture)
	var asymmetric := AnimatedSprite2D.new()
	asymmetric.sprite_frames = distinct
	for direction in [-1, 1]:
		Appearance.pose(asymmetric, false, direction, Appearance.idle_frame(asymmetric, 1.1, direction))
		var color := asymmetric.sprite_frames.get_frame_texture(asymmetric.animation, asymmetric.frame).get_image().get_pixel(0, 0)
		check(color == (Color.RED if direction < 0 else Color.BLUE) and not asymmetric.flip_h, "asymmetric idle selects its authored direction texture")
		check(asymmetric.frame == (1 if direction < 0 else 0), "each directional idle uses its own frame timing")
	asymmetric.free()
	check(Appearance.Library.FrameContract.canonical_height_px("kotone") == 172 and Appearance.Library.FrameContract.canonical_height_px("yuna") == 155, "metric dimensions 172/155")
	shell.queue_free()
	platform.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"character-presentation","checks":checks,"failures":failures,"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
