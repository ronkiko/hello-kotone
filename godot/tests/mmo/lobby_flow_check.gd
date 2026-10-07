extends SceneTree
## Two actual Godot scene consumers. Python starts services, never plays for us.
const Protocol = preload("res://scripts/mmo/protocol_v8.gd")
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
var client: Node
var pre: Node
var role := 1
var checks := 0
var sync := ""
var output := ""
var failed := false
var shell: Node
var remote_idle_results: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		print("FAIL ", label)

func wait_until(predicate: Callable, label: String, seconds: float = 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var ok: bool = predicate.call()
	check(ok, label)
	if not ok and pre != null: print("STATE ", pre.state, " ERROR ", JSON.stringify(pre.error), " GAME ", client.state, " GAME_ERROR ", JSON.stringify(client.last_error))
	return ok

func button(text: String) -> Button:
	return _find_button(current_scene, text)

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null: return found
	return null

func press(text: String) -> void:
	var node := button(text)
	check(node != null and not node.disabled, "button " + text)
	if node != null and not node.disabled:
		var ancestor: Node = node.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer: ancestor.ensure_control_visible(node)
			ancestor = ancestor.get_parent()
		await process_frame
		await process_frame
		var point := node.get_global_rect().get_center()
		check(root.get_visible_rect().has_point(point), "reachable by mouse " + text)
		var down := InputEventMouseButton.new()
		down.position = point
		down.button_index = MOUSE_BUTTON_LEFT
		down.pressed = true
		down.global_position = point
		root.push_input(down, true)
		await process_frame
		var up := InputEventMouseButton.new()
		up.position = point
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		up.global_position = point
		root.push_input(up, true)
	await process_frame

func screenshot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("peer%d-%s.png" % [role, label]))

func mark(label: String) -> void:
	var file := FileAccess.open(sync.path_join(label), FileAccess.WRITE)
	file.store_string("ready")

func verify_remote_idle(world: Node, remote_id: String, direction: int) -> bool:
	var side := "left" if direction < 0 else "right"
	var prefix := "directional-" + side
	var other_role := 3 - role
	var renderer: Node = world.platform.remote_players[remote_id]
	world.input_adapter.set_physics_process(false)
	mark(prefix + "-ready%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join(prefix + "-ready%d" % other_role)), side + " both windows ready"): return false
	var start_x: int = client.world_replica.local_player().motion.position_mm
	client.set_control(direction, direction)
	if not await wait_until(func(): return direction * (client.world_replica.local_player().motion.get("position_mm", start_x) - start_x) >= 400, side + " authoritative displacement"): return false
	client.set_control(0, direction)
	if not await wait_until(func(): return client._server_input.drive == 0 and client.state == "READY" and client.world_replica.local_player().motion.velocity_mm_s == 0, side + " acknowledged stop"): return false
	var final_x: int = client.world_replica.local_player().motion.position_mm
	var marker_path := sync.path_join(prefix + "-stop%d" % role)
	var marker := FileAccess.open(marker_path + ".tmp", FileAccess.WRITE)
	marker.store_string(str(final_x))
	marker.close()
	check(DirAccess.rename_absolute(marker_path + ".tmp", marker_path) == OK, side + " stop marker published atomically")
	var peer_stop := sync.path_join(prefix + "-stop%d" % other_role)
	if not await wait_until(func(): return FileAccess.file_exists(peer_stop), side + " peer stopped"): return false
	var peer_x := int(FileAccess.get_file_as_string(peer_stop))
	var expected := Appearance.idle_animation(direction)
	if not await wait_until(func(): return client.world_replica.view().players.get(remote_id, {}).get("motion", {}).get("position_mm", -99999) == peer_x and is_equal_approx(renderer.visual_x, renderer.target_x) and renderer.sprite.animation == expected, side + " remote settled directional idle"): return false
	if not await wait_until(func(): return world.platform.sprite.animation == expected and is_equal_approx(world.platform.character_root.position.x, world.platform.server_to_pixel(final_x)), side + " own settled directional idle"): return false
	check(client.world_replica.view().players[remote_id].motion.facing == direction and client.world_replica.view().players[remote_id].motion.velocity_mm_s == 0, side + " authoritative shared facing at rest")
	check(not renderer.sprite.flip_h and not renderer.sprite.flip_v and renderer.sprite.scale == Vector2.ONE and renderer.sprite.position == Vector2(-128, -236), side + " remote uses authored direction with canonical anchor")
	var first_frame: int = renderer.sprite.frame
	var target_x: float = renderer.target_x
	await screenshot("remote-idle-" + side)
	if DisplayServer.get_name() != "headless":
		check(FileAccess.file_exists(output.path_join("peer%d-remote-idle-%s.png" % [role, side])), side + " rendered window screenshot saved")
	if not await wait_until(func(): return renderer.sprite.animation == expected and renderer.sprite.frame != first_frame, side + " remote idle frame advances", 5.0): return false
	check(is_equal_approx(renderer.visual_x, target_x) and is_equal_approx(renderer.target_x, target_x), side + " idle animation leaves remote position unchanged")
	remote_idle_results.append({"side": side, "remote_model": renderer.sprite.get_meta("character_model_id"), "animation": String(renderer.sprite.animation), "first_frame": first_frame, "next_frame": renderer.sprite.frame, "confirmed_x": peer_x, "rendered_x": renderer.visual_x, "target_x": renderer.target_x, "flip_h": renderer.sprite.flip_h, "visual_origin": [renderer.sprite.position.x, renderer.sprite.position.y], "display_backend": DisplayServer.get_name()})
	mark(prefix + "-observed%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join(prefix + "-observed%d" % other_role)), side + " both windows observed idle"): return false
	return true

func _run() -> void:
	client = root.get_node("MmoClient")
	pre = root.get_node("Preworld")
	role = int(OS.get_environment("LOBBY09_ROLE"))
	if DisplayServer.get_name() != "headless":
		root.title = "7.11 peer %d - %s" % [role, "Kotone" if role == 1 else "Yuna"]
		root.size = Vector2i(780, 440)
		root.position = Vector2i(10 + (role - 1) * 800, 80)
	sync = OS.get_environment("LOBBY09_SYNC")
	output = OS.get_environment("LOBBY09_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	change_scene_to_file("res://scenes/mmo/login.tscn")
	await wait_until(func(): return current_scene != null, "initial Login scene")
	shell = current_scene
	shell.security.select(1)
	shell.security.item_selected.emit(1)
	shell.nickname.text = OS.get_environment("LOBBY09_ACCOUNT")
	shell.password.text = OS.get_environment("LOBBY09_PASSWORD")
	shell.ca_path.text = OS.get_environment("LOBBY09_CA")
	shell.port.value = int(OS.get_environment("LOBBY09_LOGIN_PORT"))
	shell.port.get_line_edit().text = OS.get_environment("LOBBY09_LOGIN_PORT")
	await process_frame
	await screenshot("login")
	await press("Sign in")
	if not await wait_until(func(): return pre.state == "REALMS", "TLS account Login"): quit(1); return
	check(pre.account_id != "" and client.session_id == "", "account without Game authority")
	for target in pre.realms:
		if target.status != "online":
			check(button("%s · %s" % [target.display_name, target.status]).disabled, "unavailable realm disabled")
	await screenshot("realms")
	await press("%s · online" % pre.realms[0].display_name)
	if not await wait_until(func(): return pre.state == "LOBBY", "realm handoff Lobby roster"): quit(1); return
	check(pre.roster.characters.is_empty(), "fresh account has empty roster")
	await press("Create character")
	check(pre.state == "CREATOR", "creator scene")
	check(shell.creator_stage == "MODEL" and shell.creator_payload.is_empty(), "separate local model stage")
	check(pre.roster.characters.is_empty() and client.session_id.is_empty(), "model stage has no durable or Game authority")
	var character_model_id := "kotone" if role == 1 else "yuna"
	if not await wait_until(func(): return shell.model_buttons.has(character_model_id), "creator candidate model button"): quit(1); return
	var model_button: Button = shell.model_buttons[character_model_id]
	var hover := InputEventMouseMotion.new()
	hover.position = model_button.get_global_rect().get_center()
	hover.global_position = hover.position
	root.push_input(hover, true)
	await process_frame
	check(shell.hovered_model == character_model_id, "mouse hover highlights candidate")
	await create_timer(0.3).timeout
	check(shell.model_previews[character_model_id].frame > 0, "hover runs authored preview animation")
	await screenshot("models")
	await press(character_model_id.capitalize())
	check(shell.model_selected == character_model_id and model_button.button_pressed, "explicit selected model")
	check(shell.creator_payload == pre.catalog.character_models[character_model_id].default_payload, "model specific defaults")
	await press("Customize")
	check(shell.creator_stage == "FINE", "confirm enters fine tuning")
	check(not shell.creator_choices.has("hair_style_id") if role == 2 else shell.creator_choices.has("hair_style_id"), "only model scoped fine options")
	# Back is entirely local and preserves same-model edits; switching resets them.
	shell.creator_payload.hair_color_id = "black"
	await press("Back to models")
	check(pre.roster.characters.is_empty(), "Back never mutates Registry")
	var alternate := "yuna" if role == 1 else "kotone"
	await press(alternate.capitalize())
	check(shell.creator_payload == pre.catalog.character_models[alternate].default_payload, "switch resets incompatible options")
	await press(character_model_id.capitalize())
	# Keyboard focus uses the same candidate preview as pointer hover.
	shell.model_buttons[character_model_id].grab_focus()
	await process_frame
	check(shell.hovered_model == character_model_id, "keyboard focus highlights candidate")
	await press("Customize")
	shell.creator_name_edit.text = "Silver Kotone" if role == 1 else "Black Yuna"
	shell.creator_name_edit.text_changed.emit(shell.creator_name_edit.text)
	var wanted := {"face_style_id": "bright" if role == 1 else "soft", "hair_color_id": "silver" if role == 1 else "black"}
	for key in wanted:
		var option: OptionButton = shell.creator_choices[key]
		var index: int = pre.catalog.character_models[character_model_id].options[key].find(wanted[key])
		option.select(index)
		option.item_selected.emit(index)
	check(shell.preview.get_node("SemanticAppearance").payload == shell.creator_payload, "local semantic preview")
	var chosen: Dictionary = shell.creator_payload.duplicate(true)
	await screenshot("creator")
	await press("Create")
	if not await wait_until(func(): return pre.state == "LOBBY" and pre.roster.characters.size() == 1, "create durable character"): quit(1); return
	var record: Dictionary = pre.roster.characters[0].duplicate(true)
	check(record.account_id == pre.account_id and record.character_id != pre.account_id and record.appearance_payload == chosen, "account character split and stored appearance")
	await press("1. " + record.display_name)
	if not await wait_until(func(): return not pre.selection.is_empty(), "select character"): quit(1); return
	await screenshot("roster")
	await press("Enter world")
	if not await wait_until(func(): return client.state == "READY" and current_scene.scene_file_path.ends_with("world.tscn"), "selected character World scene"): quit(1); return
	check(client.player_id == record.character_id and client.world_session.view().identity.realm_id == record.realm_id, "world identity binding")
	check(client.world_replica.local_player().character.appearance_payload == chosen, "Registry appearance in bootstrap")
	mark("ready%d" % role)
	if not await wait_until(func(): return client.world_replica.view().players.size() == 2, "two actual Godot peers"): quit(1); return
	var world: Node = current_scene
	var remote_id := ""
	for id in client.world_replica.view().players:
		if id != record.character_id: remote_id = id
	if not await wait_until(func(): return world.platform.remote_players.has(remote_id), "remote renderer"): quit(1); return
	var remote: Dictionary = client.world_replica.view().players[remote_id]
	check(remote.character.appearance_payload.character_model_id != chosen.character_model_id, "remote distinct semantic appearance")
	check(world.platform.remote_players[remote_id].sprite.get_node("SemanticAppearance").payload == remote.character.appearance_payload, "remote applies authoritative appearance")
	check(world.platform.remote_players[remote_id].sprite.get_meta("character_model_id") == remote.character.appearance_payload.character_model_id, "remote presenter model")
	check(world.platform.sprite.get_meta("character_model_id") == chosen.character_model_id, "own presenter model")
	check(world.platform.sprite.get_node("SemanticAppearance").payload == chosen, "own renderer applies appearance")
	check(not world.platform.sprite.material == world.platform.remote_players[remote_id].sprite.material, "independent appearance materials")
	world.input_adapter.set_physics_process(false)
	var initial: int = client.world_replica.local_player().motion.position_mm
	check(client.set_control(-1 if role == 1 else 1, -1 if role == 1 else 1), "separate visible avatars")
	if not await wait_until(func(): return abs(client.world_replica.local_player().motion.get("position_mm", initial) - initial) >= 600, "separated authoritative positions"): quit(1); return
	client.set_control(0, client._desired_input.facing)
	if not await wait_until(func(): return client._server_input.drive == 0 and client.state == "READY" and client.world_replica.local_player().motion.velocity_mm_s == 0, "stop before appearance screenshot"): quit(1); return
	mark("position%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join("position%d" % (3-role))), "both avatars positioned"): quit(1); return
	await screenshot("multiplayer")
	mark("observed%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join("observed%d" % (3-role))), "peer observations complete"): quit(1); return
	for direction in [-1, 1]:
		if not await verify_remote_idle(world, remote_id, direction): quit(1); return
	world.input_adapter.set_physics_process(false)
	var before: int = client.world_replica.local_player().motion.position_mm
	check(client.set_control(1, 1), "held input sent")
	if not await wait_until(func(): return client.world_replica.local_player().motion.get("position_mm", before) > before, "authoritative movement"): quit(1); return
	check(client.world_replica.local_player().character.appearance_payload == chosen, "moved preserves authoritative model")
	# Leave while input is held: drain -> stop ACK -> logout actual flush -> roster.
	await press("Leave world")
	if not await wait_until(func(): return pre.state == "LOBBY" and current_scene.scene_file_path.ends_with("login.tscn"), "Leave returns same Lobby"): quit(1); return
	check(client.session_id == "" and client._desired_input.drive == 0 and client._server_input_seq == 0, "world authority/input cleared")
	check(pre.roster.characters[0].character_id == record.character_id and pre.selection.is_empty(), "same roster fresh selection required")
	await screenshot("returned-lobby")
	await press("1. " + record.display_name)
	if not await wait_until(func(): return not pre.selection.is_empty(), "fresh post-flush selection"): quit(1); return
	await press("Enter world")
	if not await wait_until(func(): return client.state == "READY" and current_scene.scene_file_path.ends_with("world.tscn"), "both models re-enter World"): quit(1); return
	check(client.world_replica.local_player().character.appearance_payload == chosen, "re-entry keeps durable model")
	check(client._server_input_seq == 0 and client._server_input.drive == 0, "re-entry never replays input")
	if role == 1:
		await press("Leave world")
		if not await wait_until(func(): return pre.state == "LOBBY" and current_scene.scene_file_path.ends_with("login.tscn"), "second safe Lobby return"): quit(1); return
		await press("1. " + record.display_name)
		if not await wait_until(func(): return not pre.selection.is_empty(), "select after second return"): quit(1); return
		await press("Delete character…")
		var dialog: ConfirmationDialog
		for child in current_scene.get_children():
			if child is ConfirmationDialog: dialog = child
		check(dialog != null, "delete requires explicit confirmation")
		if dialog != null: dialog.confirmed.emit()
		if not await wait_until(func(): return pre.state == "LOBBY" and pre.roster.characters.is_empty(), "delete durable selected character"): quit(1); return
		await screenshot("deleted-roster")
		await press("Back to realms")
		check(pre.state == "REALMS" and pre.realm.is_empty() and pre.selection.is_empty() and pre._binding.is_empty(), "Back revokes realm authority")
		await press("Sign out")
	else:
		await press("Sign out account")
		if not await wait_until(func(): return pre.state == "LOGIN" and current_scene.scene_file_path.ends_with("login.tscn"), "account logout from World flushes first"): quit(1); return
	check(pre.state == "LOGIN" and pre.account_id == "" and client.session_id == "" and pre._binding.is_empty(), "account logout clears all authority")
	print("LOBBY09_RESULT ", JSON.stringify({"role": role, "checks": checks, "passed": not failed, "display_backend": DisplayServer.get_name(), "remote_idle": remote_idle_results}))
	quit(1 if failed else 0)
