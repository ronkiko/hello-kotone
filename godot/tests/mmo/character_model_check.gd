extends SceneTree
## Hostile catalog, client content incompatibility and card-local presentation.
const Protocol = preload("res://scripts/mmo/protocol_v8.gd")
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const Gait = preload("res://scripts/presentation/gait_animator.gd")
var checks := 0
var failures := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var kotone := {"character_model_id": "kotone", "body_variant_id": "standard", "face_style_id": "soft", "hair_style_id": "short", "hair_color_id": "chestnut"}
	var yuna := {"character_model_id": "yuna", "body_variant_id": "standard", "face_style_id": "bright", "hair_style_id": "bob", "hair_color_id": "rose"}
	check(Appearance.supported(kotone) and Appearance.supported(yuna), "two installed presenters")
	for change in [{"character_model_id": "unknown"}, {"hair_style_id": "long"}, {"hair_color_id": "chestnut"}, {"scene": "res://fake.tscn"}, {"archetype_id": "resident"}]:
		var bad := yuna.duplicate(true)
		bad.merge(change, true)
		check(not Appearance.supported(bad), "unknown/cross-model/path rejected")
	for value in [kotone, yuna]:
		var options: Dictionary = Appearance.MODELS[value.character_model_id]
		check(Appearance.catalog_model_supported(value.character_model_id, {"options": options,"default_payload":value}), "canonical catalog accepted without removed archetype field")
	var sprite := AnimatedSprite2D.new()
	root.add_child(sprite)
	check(Appearance.install(sprite, yuna), "Yuna installed")
	check(sprite.animation == &"idle_right" and sprite.sprite_frames.get_frame_count(&"idle_right") == 2, "canonical Yuna calm idle frames")
	check(is_equal_approx(sprite.sprite_frames.get_animation_speed(&"idle_right"), 0.5), "Yuna idle uses slow calm cycle")
	var gait := Gait.new()
	gait.configure(24)
	gait.update(sprite, 0, -3, -1, 0.1)
	check(sprite.animation == &"walk_left" and not sprite.flip_h and sprite.sprite_frames.get_frame_count(&"walk_left") == 8, "rendered displacement and authoritative facing select prepared left walk")
	gait.update(sprite, -3, -3, -1, 0.1)
	check(sprite.animation == &"idle_left" and not sprite.flip_h, "zero rendered displacement selects prepared directional idle")
	var push := {"contact_delta_velocity_mm_s":900,"contact_response_facing":1,
		"contact_response_tick":5,"contact_response_contacts":["p2"],"contact_impact_sources":["p2"]}
	check(gait.try_contact_reaction(sprite, "yuna", push)
		and sprite.animation == &"stumble_back" and sprite.is_playing(), "server peer response starts authored Yuna push reaction")
	check(not gait.try_contact_reaction(sprite,"yuna",push),"same physical response tick cannot replay reaction")
	# These are receiver-relative action classes, never world-left/world-right.
	for impulse_direction in [-1, 1]:
		for receiver_facing in [-1, 1]:
			var hit := {"contact_delta_velocity_mm_s":impulse_direction * 758,
				"contact_response_facing":receiver_facing,"contact_response_tick":8,
				"contact_response_contacts":["p2"],"contact_impact_sources":["p2"]}
			var expected_side := &"back" if impulse_direction == receiver_facing else &"front"
			check(Gait.impact_side(hit) == expected_side,
				"semantic impact side depends on receiver orientation, not absolute world X")
	check(Gait.impact_side({"contact_delta_velocity_mm_s":758,"contact_response_facing":1,
		"contact_response_tick":9,"contact_response_contacts":["p2"],"contact_impact_sources":[]}) == &"",
		"generic pusher slowdown never masquerades as a hit")

	for no_response in [{"contacts":["p2"]},{"contacts":["wall_max"]},{"velocity_mm_s":3000}]:
		check(not gait.try_contact_reaction(sprite,"yuna",no_response),"touch wall or motor without server response never stumbles")
	check(sprite.sprite_frames.get_frame_count(&"stumble_back")==8 and not sprite.sprite_frames.get_animation_loop(&"stumble_back"),"intended reaction has eight non-looping authored frames")
	check(not sprite.sprite_frames.has_animation(&"stumble_front") and not sprite.sprite_frames.has_animation(&"stumble_right2"),"front art deferred and obsolete world-side animation removed")
	var left_back := {"contact_delta_velocity_mm_s":-758,"contact_response_facing":-1,
		"contact_response_tick":6,"contact_response_contacts":["p2"],"contact_impact_sources":["p2"]}
	check(Gait.impact_side(left_back) == &"back" and gait.try_contact_reaction(sprite, "yuna", left_back)
		and sprite.animation == &"stumble_back" and sprite.flip_h,
		"left-moving back impact reuses mirrored back animation")
	gait.reset(sprite, -1)
	check(not sprite.flip_h and sprite.animation == &"idle_left","normal directional art clears reaction mirroring")
	var front := {"contact_delta_velocity_mm_s":758,"contact_response_facing":-1,
		"contact_response_tick":7,"contact_response_contacts":["p2"],"contact_impact_sources":["p2"]}
	check(Gait.impact_side(front) == &"front" and not gait.try_contact_reaction(sprite, "yuna", front)
		and not sprite.sprite_frames.has_animation(&"stumble_front"),
		"front impact is semantic and does not counterfeit back art")
	gait.reset(sprite,1)
	gait.update(sprite,0,0.4,1,1.0/60.0)
	gait.update(sprite,0,0,1,1.0/60.0)
	check(gait.walking and sprite.animation==&"walk_right","one zero-displacement render interval cannot flicker idle")
	gait.update(sprite,0,0,1,0.05)
	check(not gait.walking and sprite.animation==&"idle_right","bounded50ms debounce settles stop")
	check(Appearance.install(sprite, kotone), "Kotone installed")
	check(sprite.animation == &"idle_right" and sprite.sprite_frames.get_frame_count(&"idle_right") == 6, "model switch installs native package")
	var options := {"signal_id": ["steady", "pulse"]}
	var catalog := {"game_card_id": "independent", "catalog_version": 2, "appearance_schema_version": 2,
		"character_models": {"beacon": {"options": options, "default_payload": {"character_model_id": "beacon", "signal_id": "steady"}}},
		"default_character_model_id": "beacon", "initial_spawn_profiles": ["default"], "default_spawn_profile": "default"}
	check(Protocol.catalog(catalog), "generic independent model catalog")
	check(not Appearance.model_supported("beacon"), "server-valid model without local content has no fallback")
	for change in [{"character_models": {}}, {"default_character_model_id": "unknown"}, {"catalog_version": 1}, {"appearance_schema_version": 1}, {"options": options}, {"legacy_empty_policy": "default"}]:
		var bad := catalog.duplicate(true)
		bad.merge(change, true)
		check(not Protocol.catalog(bad), "obsolete/unbounded catalog rejected")
	var bad := catalog.duplicate(true)
	bad.character_models.beacon.default_payload.character_model_id = "foreign"
	check(not Protocol.catalog(bad), "default model identity cannot disagree")
	bad = catalog.duplicate(true)
	bad.character_models.beacon.options.signal_id = ["steady", "steady"]
	check(not Protocol.catalog(bad), "duplicate model options rejected")
	sprite.queue_free()
	print(JSON.stringify({"suite": "character-models", "checks": checks, "failures": failures, "result": "PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
