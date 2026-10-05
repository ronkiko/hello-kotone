extends SceneTree
## Actual shared Creator/own/remote package, root and gait invariants.
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const Gait = preload("res://scripts/presentation/gait_animator.gd")
const Platform = preload("res://scripts/presentation/platform_world.gd")
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
	var platform := Platform.new()
	root.add_child(platform)
	platform.set_process(false)
	var document := {"schema_version":1,"map_id":"city/apartment","content_version":1,"min_x":0,"max_x":100,"spawn_x":50,"units_per_meter":1,"content_hash":"4f465435cbb8eb3e5154a4776be29e7aee4f73376e00fb26299bfbf0cfcd361b"}
	platform.set_movement_rules({"movement":{"step_units":1,"min_move_interval_ms":200}})
	var view := {"map":{"map_id":document.map_id,"content_version":1,"content_hash":document.content_hash},"confirmed_local_x":50,"epoch":"e1","local_player_id":"p1","players":{}}
	for model in ["kotone", "yuna"]:
		var definition := {"game_card_id":"hello-kotone","realm_id":"local","character_id":"p1","display_name":"local","appearance_schema_version":2,"appearance_payload":payload(model)}
		# Current Protocol.character includes the durable definition shape used by v7.
		var player := {"player_id":"p1","nickname":"local","zone_id":"city/apartment","x":50,"character":definition}
		var remote := player.duplicate(true)
		remote.player_id = "p2"
		remote.character.character_id = "p2"
		remote.character.display_name = "remote"
		remote.nickname = "remote"
		view.players = {"p1":player,"p2":remote}
		check(platform.project(document,view), model + " current character projection")
		if not platform.remote_players.has("p2"): continue
		shell._preview(payload(model))
		var own: AnimatedSprite2D = platform.sprite
		var other: AnimatedSprite2D = platform.remote_players.p2.sprite
		check(shell.preview.sprite_frames == own.sprite_frames and other.sprite_frames == own.sprite_frames, model + " Creator own remote same resource")
		check(own.scale == Vector2.ONE and own.position == Vector2(-128,-236), model + " canonical visual transform")
		check(shell.preview.get_parent().scale == own.get_parent().scale and other.get_parent().scale == own.get_parent().scale, model + " common display transform")
		var expected_height := Appearance.display_height_px(model)
		check(is_equal_approx(platform.local_label.position.y, Platform.FLOOR_Y - expected_height - 18), model + " local label follows metric height")
		check(is_equal_approx(platform.remote_players.p2.identity.position.y, -expected_height - 18), model + " remote label follows metric height")
		var position: Vector2 = platform.character_root.position
		var gait := Gait.new()
		gait.configure(10)
		for facing in [-1,1]:
			for index in range(own.sprite_frames.get_frame_count(Appearance.walk_animation(facing))):
				Appearance.pose(own,true,facing,index)
				check(own.position == Vector2(-128,-236) and own.scale == Vector2.ONE and platform.character_root.position == position, model + " walk frame preserves anchor")
		gait.update(own,0,3,5,1,.1)
		var frame := own.frame
		gait.update(own,3,3,5,1,.5)
		check(own.frame == frame and not own.is_playing(), model + " blocked body freezes gait")
		gait.update(own,3,3,3,0,.1)
		check(own.animation == &"idle" and platform.character_root.position == position, model + " release preserves root")
		for index in range(own.sprite_frames.get_frame_count(&"idle")):
			Appearance.pose(own,false,0,index)
			check(own.position == Vector2(-128,-236) and own.scale == Vector2.ONE, model + " idle preserves anchor")
	check(Appearance.Library.FrameContract.canonical_height_px("kotone") == 172 and Appearance.Library.FrameContract.canonical_height_px("yuna") == 155, "metric dimensions 172/155")
	shell.queue_free()
	platform.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"character-presentation","checks":checks,"failures":failures,"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
