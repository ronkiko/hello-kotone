extends SceneTree
## Two actual Godot scene consumers. Python starts services, never plays for us.
const Protocol = preload("res://scripts/mmo/protocol_v7.gd")
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
var client: Node
var pre: Node
var role := 1
var checks := 0
var sync := ""
var output := ""
var failed := false
var shell: Node

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

func _run() -> void:
	client = root.get_node("MmoClient")
	pre = root.get_node("Preworld")
	role = int(OS.get_environment("LOBBY09_ROLE"))
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
	shell.creator_name_edit.text = "Silver Kotone" if role == 1 else "Black Kotone"
	shell.creator_name_edit.text_changed.emit(shell.creator_name_edit.text)
	var wanted := {"face_style_id": "bright" if role == 1 else "soft", "hair_style_id": "short" if role == 1 else "long", "hair_color_id": "silver" if role == 1 else "black"}
	for key in wanted:
		var option: OptionButton = shell.creator_choices[key]
		var index: int = pre.catalog.options[key].find(wanted[key])
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
	check(remote.character.appearance_payload.hair_color_id != chosen.hair_color_id, "remote distinct semantic appearance")
	check(world.platform.remote_players[remote_id].sprite.get_node("SemanticAppearance").payload == remote.character.appearance_payload, "remote applies authoritative appearance")
	check(world.platform.sprite.get_node("SemanticAppearance").payload == chosen, "own renderer applies appearance")
	check(not world.platform.sprite.material == world.platform.remote_players[remote_id].sprite.material, "independent appearance materials")
	var initial: int = client.world_replica.local_player().x
	check(client.set_input("right" if role == 1 else "left"), "separate visible avatars")
	if not await wait_until(func(): return abs(client.world_replica.local_player().get("x", initial) - initial) >= 6, "separated authoritative positions"): quit(1); return
	client.set_input("stop")
	if not await wait_until(func(): return client._server_input == "stop" and client.state == "READY", "stop before appearance screenshot"): quit(1); return
	mark("position%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join("position%d" % (3-role))), "both avatars positioned"): quit(1); return
	await screenshot("multiplayer")
	mark("observed%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join("observed%d" % (3-role))), "peer observations complete"): quit(1); return
	var before: int = client.world_replica.local_player().x
	check(client.set_input("right"), "held input sent")
	if not await wait_until(func(): return client.world_replica.local_player().get("x", before) > before, "authoritative movement"): quit(1); return
	# Leave while input is held: drain -> stop ACK -> logout actual flush -> roster.
	await press("Leave world")
	if not await wait_until(func(): return pre.state == "LOBBY" and current_scene.scene_file_path.ends_with("login.tscn"), "Leave returns same Lobby"): quit(1); return
	check(client.session_id == "" and client._desired_input == "stop" and client._server_input_seq == 0, "world authority/input cleared")
	check(pre.roster.characters[0].character_id == record.character_id and pre.selection.is_empty(), "same roster fresh selection required")
	await screenshot("returned-lobby")
	await press("1. " + record.display_name)
	if not await wait_until(func(): return not pre.selection.is_empty(), "fresh post-flush selection"): quit(1); return
	if role == 1:
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
		await press("Enter world")
		if not await wait_until(func(): return client.state == "READY" and current_scene.scene_file_path.ends_with("world.tscn"), "re-enter World"): quit(1); return
		check(client._server_input_seq == 0 and client._server_input == "stop", "no input replay on re-entry")
		await press("Sign out account")
		if not await wait_until(func(): return pre.state == "LOGIN" and current_scene.scene_file_path.ends_with("login.tscn"), "account logout from World flushes first"): quit(1); return
	check(pre.state == "LOGIN" and pre.account_id == "" and client.session_id == "" and pre._binding.is_empty(), "account logout clears all authority")
	print("LOBBY09_RESULT ", JSON.stringify({"role": role, "checks": checks, "passed": not failed}))
	quit(1 if failed else 0)
