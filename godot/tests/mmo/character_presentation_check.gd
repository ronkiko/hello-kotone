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
		if model == "kotone":
			var valid_scale: float = platform.pixels_per_meter
			platform.pixels_per_meter = 0.0
			check(not platform.project(document,view),
				"missing canonical sprite metric refuses projection instead of dividing by zero")
			platform.pixels_per_meter = valid_scale
		check(platform.project(document,view), model + " current character projection")
		if not platform.remote_players.has("p2"): continue
		var physical := preload("res://tests/mmo/replica_check.gd").physics(model)
		check(physical.physics_profile_revision == "hello_kotone_physics_v4"
			and physical.motor.motor_profile_id == model + "_motor_v3",
			model + " accepts only refreshed walk motor binding")
		check(platform._movement.mass_g == physical.body.mass_g and platform._movement.top_speed_mm_s == physical.motor.top_speed_mm_s, model + " predictor uses selected server profile")
		check(is_equal_approx(platform.pixels_per_meter, Appearance.world_pixels_per_meter())
			and is_equal_approx(platform.pixels_per_meter, 48.0),
			model + " world projection shares sprite metric contract")
		check(is_equal_approx(platform.character_collision.shape.size.x,
			physical.body.collision_width_mm * platform.pixels_per_meter / 1000.0),
			model + " native owner width from body")
		check(is_equal_approx(platform.character_collision.shape.size.y,
			physical.body.collision_height_mm * platform.pixels_per_meter / 1000.0)
			and is_equal_approx(platform.character_collision.shape.size.y, Appearance.display_height_px(model)),
			model + " displayed body height matches native collider height without scaling server physics")
		check(platform.character_collision.position == Vector2(0.0,
			-platform.character_collision.shape.size.y / 2.0),
			model + " physical ground pivot remains aligned with visual root")
		check(platform._pixel_to_server_mm(platform.server_to_pixel(50000)) == 50000,
			model + " canonical metre position survives projection roundtrip")
		check(is_equal_approx(platform.remote_players.p2.gait.cycle_pixels,
			physical.motor.top_speed_mm_s * platform.pixels_per_meter / 1000.0),
			model + " remote gait uses the same projection as owner")
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
			var physical_response := {"contact_delta_velocity_mm_s":758,"contact_response_tick":12,"contact_response_facing":1,
				"contact_response_contacts":["p1"],"contact_impact_sources":["p1"]}
			check(remote_node.gait.try_contact_reaction(other,"yuna",physical_response), "remote starts received mass-aware reaction")
			var damage_response := physical_response.duplicate(true)
			damage_response["contact_impact_impulse_g_mm_s"] = 37900000
			damage_response["contact_damage"] = 8
			var received_damage := damage_response.duplicate(true)
			received_damage["player_id"] = "p2"
			received_damage["position_mm"] = int(remote.motion.position_mm)
			var first_hit := {"event":"motion_frame","data":{"players":[received_damage]}}
			platform._queue_impact_display(first_hit)
			check(platform.impact_numbers.get_child_count() == 1
				and platform.impact_numbers.get_child(0).text == "-8",
				"one global renderer displays remote damage immediately")
			platform._queue_impact_display(first_hit)
			check(platform.impact_numbers.get_child_count() == 1,
				"ingress deduplicates repeated remote hit tick")
			remote_node.render_at(remote_node.position.x, damage_response, 0.016)
			check(platform.impact_numbers.get_child_count() == 1,
				"remote gait interpolation cannot spawn duplicate damage")
			var local_hit := received_damage.duplicate(true)
			local_hit["player_id"] = "p1"
			local_hit["contact_damage"] = 4
			local_hit["contact_impact_impulse_g_mm_s"] = 20000000
			local_hit["position_mm"] = 52000
			platform._queue_impact_display({"event":"motion_frame",
				"data":{"players":[local_hit]}})
			check(platform.impact_numbers.get_child_count() == 2
				and platform.impact_numbers.get_child(1).text == "-4",
				"another character with same impact tick is independently displayed")
			var next_damage := received_damage.duplicate(true)
			next_damage["contact_response_tick"] = 13
			next_damage["contact_damage"] = 5
			next_damage["contact_impact_impulse_g_mm_s"] = 25000000
			platform._queue_impact_display({"event":"motion_frame",
				"data":{"players":[next_damage]}})
			check(platform.impact_numbers.get_child_count() == 3
				and platform.impact_numbers.get_child(2).text == "-5",
				"second accepted remote hit renders immediately without a per-character FIFO")
			var contact_player := remote.duplicate(true)
			contact_player.motion.simulation_tick = 15
			contact_player.contacts = ["p1"]
			remote_node.project(contact_player,remote_node.position.x,"e1|city/apartment|1",50000,
				int(physical.motor.top_speed_mm_s))
			check(remote_node.gait.last_contact_response_tick == 12 and other.animation == Gait.BACK_REACTION, "position rebase preserves consumed event and playing reaction")
			check(not remote_node.gait.try_contact_reaction(other,"yuna",physical_response), "contact rebase does not replay consumed event")
			remote_node.set_suspended(true)
			check(remote_node.gait.last_contact_response_tick == 0 and remote_node.timeline._responses.is_empty(), "visit suspension clears causal response scope")
			# Damage rendering is owned by World, not the remote character.
			check(platform.impact_numbers.get_parent() == platform
				and not remote_node.has_node("ImpactNumbers"),
				"only one global damage renderer exists for all players")
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
			"contact_response_tick":7,"contact_response_contacts":["p2"],"contact_impact_sources":["p2"]}
		var reaction_started: bool = push_gait.try_contact_reaction(own, model, push)
		if model == "yuna":
			check(reaction_started and own.animation == &"stumble_back" and own.is_playing(), model + " server contact response selects authored Yuna reaction")
			push_gait.update(own, 0, 4, 1, .1)
			check(own.animation == &"stumble_back", model + " reaction holds over gait until SpriteFrames completes it")
			own.set_frame_and_progress(4, 0.5)
			var second_push := {"contact_delta_velocity_mm_s":758,"contact_response_facing":1,
				"contact_response_tick":8,"contact_response_contacts":["p2"],"contact_impact_sources":["p2"]}
			check(push_gait.try_contact_reaction(own, model, second_push)
				and own.animation == &"stumble_back" and own.frame == 0
				and push_gait.last_contact_response_tick == 8,
				model + " later authoritative impact restarts reaction from frame zero")
			check(not push_gait.try_contact_reaction(own, model, second_push),
				model + " duplicate response tick cannot restart reaction twice")
			var left_back := {"contact_delta_velocity_mm_s":-758,"contact_response_facing":-1,
				"contact_response_tick":9,"contact_response_contacts":["p2"],"contact_impact_sources":["p2"]}
			check(Gait.impact_side(left_back) == &"back"
				and push_gait.try_contact_reaction(own, model, left_back)
				and own.animation == Gait.BACK_REACTION and own.flip_h
				and push_gait.last_contact_response_tick == 9,
				model + " back impact plays the same art mirrored for opposite world direction")
			push_gait.update(own, 0, -4, -1, .1)
			check(own.animation == Gait.BACK_REACTION and own.flip_h,
				model + " mirrored back reaction is not overwritten by walking")
			var front_impact := {"contact_delta_velocity_mm_s":758,"contact_response_facing":-1,
				"contact_response_tick":10,"contact_response_contacts":["p2"],"contact_impact_sources":["p2"]}
			check(Gait.impact_side(front_impact) == &"front"
				and not push_gait.try_contact_reaction(own, model, front_impact)
				and not own.sprite_frames.has_animation(Gait.FRONT_REACTION),
				model + " front impact never substitutes the wrong back reaction")
			check(push_gait.last_contact_response_tick == 9,
				model + " missing front art does not consume the last played back event")
			var pusher_slowdown := {"contact_delta_velocity_mm_s":900,"contact_response_facing":1,
				"contact_response_tick":11,"contact_response_contacts":["p2"],"contact_impact_sources":[]}
			check(Gait.impact_side(pusher_slowdown) == &""
				and not push_gait.try_contact_reaction(own, model, pusher_slowdown),
				model + " ordinary contact deceleration is not a physical impact")
			check(push_gait.last_contact_response_tick == 9,
				model + " non-shove response cannot consume the back reaction")
			push_gait.reset(own, -1)
			check(not own.flip_h and own.animation == Appearance.idle_animation(-1),
				model + " regular authored left idle clears temporary reaction mirroring")
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
