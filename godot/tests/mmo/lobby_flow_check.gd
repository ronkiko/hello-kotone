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
var remote_onset_results: Array = []
var contact_results: Dictionary = {}
var owner_ux_results: Array = []

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
	file.close()

func verify_remote_idle(world: Node, remote_id: String, direction: int) -> bool:
	var side := "left" if direction < 0 else "right"
	var prefix := "directional-" + side
	var other_role := 3 - role
	var renderer: Node = world.platform.remote_players[remote_id]
	world.input_adapter.set_physics_process(false)
	if not await wait_until(func():
		return client.world_replica.view().players.get(remote_id, {}).get("motion", {}).get("velocity_mm_s", 1) == 0 \
			and is_equal_approx(renderer.visual_x, renderer.target_x), side + " remote timeline settled before measurement"):
		return false
	client.set_control(0, direction)
	if not await wait_until(func():
		var motion: Dictionary = client.world_replica.local_player().motion
		return motion.facing == direction and motion.velocity_mm_s == 0,
		side + " stationary facing baseline"):
		return false
	mark(prefix + "-baseline-ready%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join(prefix + "-baseline-ready%d" % other_role)), side + " both windows set facing baseline"):
		return false
	var baseline_ready := await wait_until(func():
		var motion: Dictionary = client.world_replica.view().players.get(remote_id, {}).get("motion", {})
		return motion.get("facing", 0) == direction \
			and renderer.sprite.animation == Appearance.idle_animation(direction),
		side + " baseline facing reaches remote presenter")
	if not baseline_ready:
		print("REMOTE BASELINE DIAGNOSTIC ", JSON.stringify({
			"role": role, "direction": direction,
			"remote_motion": client.world_replica.view().players.get(remote_id, {}).get("motion", {}),
			"animation": String(renderer.sprite.animation), "gait_facing": renderer.gait.facing,
			"gait_walking": renderer.gait.walking, "reaction_tick": renderer.gait.last_contact_response_tick,
			"sprite_playing": renderer.sprite.is_playing(),
			"timeline_sample": renderer.timeline.sample_at(Time.get_ticks_usec()),
			"timeline_metrics": renderer.timeline.metrics()}))
		return false
	mark(prefix + "-baseline-observed%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join(prefix + "-baseline-observed%d" % other_role)),
		side + " both windows observed baseline facing"):
		return false
	var tap_facing := -direction
	var owner_tap_x: int = client.world_replica.local_player().motion.position_mm
	var remote_tap_x: int = client.world_replica.view().players[remote_id].motion.position_mm
	client.set_control(0, tap_facing)
	if not await wait_until(func():
		var motion: Dictionary = client.world_replica.local_player().motion
		return motion.facing == tap_facing and motion.velocity_mm_s == 0 and motion.position_mm == owner_tap_x \
			and world.platform.sprite.animation == Appearance.idle_animation(tap_facing), side + " stationary tap reaches owner facing"):
		return false
	mark(prefix + "-tap-ready%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join(prefix + "-tap-ready%d" % other_role)), side + " both windows applied short tap"):
		return false
	if not await wait_until(func():
		var motion: Dictionary = client.world_replica.view().players.get(remote_id, {}).get("motion", {})
		return motion.get("facing", 0) == tap_facing and motion.get("velocity_mm_s", -1) == 0 \
			and motion.get("position_mm", -1) == remote_tap_x and renderer.sprite.animation == Appearance.idle_animation(tap_facing),
		side + " stationary tap is shared with remote without displacement"):
		return false
	check(client.world_replica.local_player().motion.position_mm == owner_tap_x
		and client.world_replica.view().players[remote_id].motion.position_mm == remote_tap_x,
		side + " short tap creates no phantom movement")
	mark(prefix + "-tap-observed%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join(prefix + "-tap-observed%d" % other_role)),side+" both peers observed stationary tap"): return false
	await screenshot("short-tap-" + side)
	client.set_control(0, direction)
	if not await wait_until(func(): return client.world_replica.local_player().motion.facing == direction,
		side + " restore authoritative facing after tap"):
		return false
	mark(prefix + "-restore-ready%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join(prefix + "-restore-ready%d" % other_role)), side + " both windows restore facing"):
		return false
	if not await wait_until(func():
		var motion: Dictionary = client.world_replica.view().players.get(remote_id, {}).get("motion", {})
		return motion.get("facing", 0) == direction \
			and renderer.sprite.animation == Appearance.idle_animation(direction),
		side + " restored facing reaches remote presenter"):
		return false
	mark(prefix + "-ready%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join(prefix + "-ready%d" % other_role)), side + " both windows ready"): return false
	var go_path := sync.path_join(prefix + "-go")
	if role == 1:
		var go_file := FileAccess.open(go_path, FileAccess.WRITE)
		go_file.store_string(str(Time.get_unix_time_from_system() + 0.5))
		go_file.close()
	elif not await wait_until(func(): return FileAccess.file_exists(go_path), side + " synchronized movement start"):
		return false
	var go_at := float(FileAccess.get_file_as_string(go_path))
	while Time.get_unix_time_from_system() < go_at:
		await process_frame
	var start_x: int = client.world_replica.local_player().motion.position_mm
	var start_usec := Time.get_ticks_usec()
	var initial_remote_x: float = renderer.visual_x
	var remote_sample_usec := -1
	var remote_onset_usec := -1
	client.set_control(direction, direction)
	var owner_previous: float = world.platform.character_root.position.x+world.platform.visual_layer.position.x
	var max_reverse_mm := 0.0
	var negative_steps := 0
	var ux_trace: Array = []
	var movement_deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_usec()-start_usec<1000000 and Time.get_ticks_msec()<movement_deadline:
		var owner_x: float = world.platform.character_root.position.x+world.platform.visual_layer.position.x
		var signed_mm: float = direction*(owner_x-owner_previous)*(1000.0 / Appearance.world_pixels_per_meter())
		if ux_trace.size()<1500: ux_trace.append(world.platform.prediction_diagnostics().merged({"signed_delta_mm":signed_mm}))
		if signed_mm < -0.1:
			negative_steps+=1
			max_reverse_mm=maxf(max_reverse_mm,-signed_mm)
		owner_previous=owner_x
		if remote_sample_usec < 0 and renderer.last_motion_sample_received_usec >= start_usec:
			remote_sample_usec = renderer.last_motion_sample_received_usec
		if remote_sample_usec >= 0 and remote_onset_usec < 0 and absf(renderer.visual_x - initial_remote_x) >= 0.001:
			remote_onset_usec = Time.get_ticks_usec()
		await process_frame
	if direction * (int(client.world_replica.local_player().motion.get("position_mm", start_x)) - start_x) < 400:
		check(false, side + " authoritative displacement")
		return false
	check(remote_sample_usec >= 0 and remote_onset_usec >= remote_sample_usec,
		side + " remote observer records sample and visible onset")
	if remote_sample_usec >= 0 and remote_onset_usec >= remote_sample_usec:
		var onset_ms := float(remote_onset_usec - remote_sample_usec) / 1000.0
		check(onset_ms <= 117.0, side + " remote onset meets 100 ms buffer + render budget")
		remote_onset_results.append({"side": side, "sample_to_onset_ms": onset_ms})
	client.set_control(0, direction)
	var release_deadline := Time.get_ticks_msec()+1000
	while Time.get_ticks_msec()<release_deadline:
		var owner_x: float = world.platform.character_root.position.x+world.platform.visual_layer.position.x
		var signed_mm: float = direction*(owner_x-owner_previous)*(1000.0 / Appearance.world_pixels_per_meter())
		if ux_trace.size()<1500: ux_trace.append(world.platform.prediction_diagnostics().merged({"signed_delta_mm":signed_mm}))
		if signed_mm < -0.1:
			negative_steps+=1
			max_reverse_mm=maxf(max_reverse_mm,-signed_mm)
		owner_previous=owner_x
		await process_frame
	var trace_file := FileAccess.open(output.path_join("owner-%d-%s.json" % [role,side]),FileAccess.WRITE)
	trace_file.store_string(JSON.stringify(ux_trace))
	trace_file.close()
	owner_ux_results.append({"side":side,"reverse_steps":negative_steps,"max_reverse_mm":max_reverse_mm})
	check(negative_steps==0,side+" loopback owner hold1s/release signed render monotonic")
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

func verify_peer_push(world: Node, remote_id: String) -> bool:
	client.set_control(0,1)
	if not await wait_until(func(): return client._server_input.drive==0 and client.state=="READY" \
		and client.world_replica.local_player().motion.velocity_mm_s==0,"push stationary right-facing baseline"): return false
	mark("push-ready%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join("push-ready%d" % (3-role))),"both push baselines ready"): return false
	var yuna_id: String = client.player_id if role==2 else remote_id
	var renderer: Node = world.platform if role==2 else world.platform.remote_players[remote_id]
	var gait: RefCounted = renderer._gait if role==2 else renderer.gait
	var response_ticks: Array[int] = []
	var reaction_ticks: Array[int] = []
	var strongest_response := 0
	var contact_at := -1
	var reverse_after_contact := 0
	var max_reverse_mm := 0.0
	var release_sent := false
	var release_seq := -1
	var release_applied_tick := -1
	var repress_sent := false
	var repress_seq := -1
	var repress_applied_tick := -1
	var before: float = world.platform.character_root.position.x+world.platform.visual_layer.position.x
	if role==1: client.set_control(1,1)
	var deadline := Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		var frame_sample: Dictionary = client.world_replica.latest_frame_sample(yuna_id)
		var response_tick := int(frame_sample.get("contact_response_tick",0))
		var response_delta := int(frame_sample.get("contact_delta_velocity_mm_s",0))
		if response_delta>=300 and response_tick>0 and not response_ticks.has(response_tick):
			response_ticks.append(response_tick)
			strongest_response=maxi(strongest_response,response_delta)
			# contact_response is emitted only by authoritative peer contact. The
			# 20-Hz snapshot contact-membership sample may legitimately miss a short
			# 60-Hz impact, so use the causal response fact for contact occurrence.
			if contact_at<0:
				contact_at=Time.get_ticks_msec()
		var consumed_tick := int(gait.last_contact_response_tick)
		if consumed_tick>0 and not reaction_ticks.has(consumed_tick):
			reaction_ticks.append(consumed_tick)
		var rendered: float = world.platform.character_root.position.x+world.platform.visual_layer.position.x
		var signed_mm: float = (rendered-before)*(1000.0 / Appearance.world_pixels_per_meter())
		if contact_at>=0 and Time.get_ticks_msec()-contact_at>300 and signed_mm < -0.1:
			reverse_after_contact+=1
			max_reverse_mm=maxf(max_reverse_mm,-signed_mm)
		before=rendered
		# Exercise the actual player sequence: first impact -> applied release ->
		# short release interval -> repress. Same-contact force transmission is
		# covered by the server kernel; this TLS path proves a fresh impacts are not manufactured by repress.
		if role==1 and response_ticks.size()>=1 and not release_sent:
			check(client.set_control(0,1),"pusher release request accepted")
			release_sent=true
		if role==1 and release_sent and release_seq<0 and client._server_input.drive==0:
			release_seq=client._server_input_seq
		if role==1 and release_seq>=0 and release_applied_tick<0 \
			and int(client.world_replica.local_player().motion.last_applied_control_seq)>=release_seq:
			release_applied_tick=int(client.world_replica.local_player().motion.simulation_tick)
		if role==1 and release_applied_tick>=0 and not repress_sent \
			and int(client.world_replica.local_player().motion.simulation_tick)>=release_applied_tick+2:
			check(client.set_control(1,1),"pusher repress request accepted")
			repress_sent=true
		if role==1 and repress_sent and repress_seq<0 and client._server_input.drive==1:
			repress_seq=client._server_input_seq
		if role==1 and repress_seq>=0 and repress_applied_tick<0 \
			and int(client.world_replica.local_player().motion.last_applied_control_seq)>=repress_seq:
			repress_applied_tick=int(client.world_replica.local_player().motion.simulation_tick)
		# Only actual new body collisions may create impact events. A later
		# release/repress while still touching is *not* a second physical hit.
		# Give delayed observer presentation time to consume any causal facts.
		if role==1 and repress_applied_tick>=0 and not response_ticks.is_empty() \
			and reaction_ticks == response_ticks \
			and int(client.world_replica.local_player().motion.simulation_tick)>=repress_applied_tick+30:
			break
		if role==2 and not response_ticks.is_empty() and reaction_ticks == response_ticks \
			and contact_at>=0 and Time.get_ticks_msec()-contact_at>850:
			break
		await process_frame
	if role==1: client.set_control(0,1)
	check(contact_at>=0,"authoritative peer contact produces a causal response")
	check(strongest_response>=300 and strongest_response<1300,"Yuna contact delta reflects physical approach, not an 8400-mm/s motor boost")
	if role==1:
		check(release_applied_tick>=0 and repress_applied_tick>release_applied_tick,
			"release and repress are both observed on authoritative applied-control boundaries")
	else:
		check(not response_ticks.is_empty(), "observer receives measured physical impact")
	check(not reaction_ticks.is_empty(),"Yuna owner and observer consume the actual impact reaction")
	check(reaction_ticks == response_ticks,"presentation consumes each observed physical impact tick exactly once")
	check(reverse_after_contact==0,"repeated peer knockback has no periodic owner snap back")
	mark("push-stopped%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join("push-stopped%d" % (3-role))),"both push observations complete"): return false
	if not await wait_until(func(): return client.world_replica.local_player().motion.velocity_mm_s==0 \
		and renderer.sprite.animation==Appearance.idle_animation(1),"reaction returns to normal directional idle"): return false
	contact_results={"response_ticks":response_ticks,"reaction_ticks":reaction_ticks,
		"strongest_response_delta_mm_s":strongest_response,
		"release_applied_tick":release_applied_tick if role==1 else null,
		"repress_applied_tick":repress_applied_tick if role==1 else null,
		"reverse_after_contact":reverse_after_contact,"max_reverse_mm":max_reverse_mm}
	var report := FileAccess.open(sync.path_join("push-result%d" % role),FileAccess.WRITE)
	report.store_string(JSON.stringify(contact_results))
	report.close()
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join("push-result%d" % (3-role))),"peer push report ready"): return false
	var other: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sync.path_join("push-result%d" % (3-role))))
	# Native JSON parses diagnostic numbers as floats; compare typed tick values.
	var other_response_ticks: Array[int] = []
	for tick in other.response_ticks: other_response_ticks.append(int(tick))
	check(other_response_ticks==response_ticks,"owner and observer share the same sequence of causal server physical impact ticks")
	await screenshot("real-peer-push")
	return true

func verify_yuna_pushes_kotone(world: Node, remote_id: String) -> bool:
	# After Kotone->Yuna, Yuna is on the right. Drive her left into stationary
	# Kotone: this is the exact inverse role that manual acceptance exposed.
	client.set_control(0,-1)
	if not await wait_until(func(): return client._server_input.drive==0 and client.state=="READY" \
		and client.world_replica.local_player().motion.velocity_mm_s==0 \
		and client.world_replica.local_player().motion.facing==-1,
		"inverse push stationary left-facing baseline"): return false
	mark("inverse-push-ready%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join("inverse-push-ready%d" % (3-role))),
		"both peers ready for Yuna pusher inverse case"): return false
	var yuna_id: String = client.player_id if role==2 else remote_id
	var kotone_id: String = client.player_id if role==1 else remote_id
	var yuna_renderer: Node = world.platform if role==2 else world.platform.remote_players[remote_id]
	var yuna_gait: RefCounted = yuna_renderer._gait if role==2 else yuna_renderer.gait
	var players: Dictionary = client.world_replica.view().players
	check(int(players[yuna_id].motion.position_mm) > int(players[kotone_id].motion.position_mm),
		"inverse case starts with Yuna physically right of Kotone")
	var reaction_tick_before := int(yuna_gait.last_contact_response_tick)
	var saw_kotone_shove := false
	var saw_yuna_contact_response := false
	var yuna_wrong_impact_sources := 0
	var reverse_steps := 0
	var contact_at := -1
	var before: float = world.platform.character_root.position.x+world.platform.visual_layer.position.x \
		if role==2 else world.platform.remote_players[remote_id].visual_x
	if role==2:
		check(client.set_control(-1,-1),"Yuna pusher left drive accepted")
	var deadline := Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		var yuna_sample: Dictionary = client.world_replica.latest_frame_sample(yuna_id)
		var kotone_sample: Dictionary = client.world_replica.latest_frame_sample(kotone_id)
		var yuna_tick := int(yuna_sample.get("contact_response_tick",0))
		var yuna_sources: Array = yuna_sample.get("contact_impact_sources",[])
		var kotone_sources: Array = kotone_sample.get("contact_impact_sources",[])
		if yuna_tick>0 and int(yuna_sample.get("contact_delta_velocity_mm_s",0))!=0:
			saw_yuna_contact_response=true
			if contact_at<0: contact_at=Time.get_ticks_msec()
		if not yuna_sources.is_empty():
			yuna_wrong_impact_sources += 1
		if kotone_sources.has(yuna_id):
			saw_kotone_shove=true
			if contact_at<0: contact_at=Time.get_ticks_msec()
		var rendered: float = world.platform.character_root.position.x+world.platform.visual_layer.position.x \
			if role==2 else world.platform.remote_players[remote_id].visual_x
		var signed_mm: float = -(rendered-before)*(1000.0 / Appearance.world_pixels_per_meter())
		if contact_at>=0 and signed_mm < -0.1:
			reverse_steps += 1
		before=rendered
		if saw_kotone_shove and Time.get_ticks_msec()-contact_at>350:
			break
		await process_frame
	if role==2:
		client.set_control(0,-1)
	check(saw_kotone_shove,"Yuna pusher creates authoritative shove on Kotone target")
	check(saw_yuna_contact_response,"Yuna pusher still receives ordinary mass/contact response fact")
	check(yuna_wrong_impact_sources==0,"Yuna pusher is never labeled as shove recipient")
	check(int(yuna_gait.last_contact_response_tick)==reaction_tick_before,
		"Yuna pusher never consumes her own contact response as stumble reaction")
	check(reverse_steps==0,"Yuna pusher render never moves opposite to held left drive after contact")
	mark("inverse-push-stopped%d" % role)
	if not await wait_until(func(): return FileAccess.file_exists(sync.path_join("inverse-push-stopped%d" % (3-role))),
		"both peers finish Yuna pusher inverse case"): return false
	if role==2 and not await wait_until(func(): return client._server_input.drive==0 \
		and client.world_replica.local_player().motion.velocity_mm_s==0,
		"Yuna pusher authoritative stop"): return false
	contact_results["yuna_pusher"]={"saw_target_shove":saw_kotone_shove,
		"saw_pusher_response":saw_yuna_contact_response,"wrong_impact_sources":yuna_wrong_impact_sources,
		"reaction_tick_before":reaction_tick_before,"reaction_tick_after":int(yuna_gait.last_contact_response_tick),
		"reverse_steps":reverse_steps}
	await screenshot("yuna-pushes-kotone")
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
	if not await wait_until(func(): return shell.model_selected == character_model_id and model_button.button_pressed,
		"explicit selected model"): quit(1); return
	check(shell.creator_payload == pre.catalog.character_models[character_model_id].default_payload, "model specific defaults")
	await press("Customize")
	if not await wait_until(func(): return shell.creator_stage == "FINE" and shell.creator_name_edit != null,
		"confirm enters fine tuning"): quit(1); return
	check(not shell.creator_choices.has("hair_style_id") if role == 2 else shell.creator_choices.has("hair_style_id"), "only model scoped fine options")
	# Back is entirely local and preserves same-model edits; switching resets them.
	shell.creator_payload.hair_color_id = "black"
	await press("Back to models")
	if not await wait_until(func(): return shell.creator_stage == "MODEL" and shell.model_buttons.has(character_model_id),
		"Back returns to model stage"): quit(1); return
	check(pre.roster.characters.is_empty(), "Back never mutates Registry")
	var alternate := "yuna" if role == 1 else "kotone"
	await press(alternate.capitalize())
	if not await wait_until(func(): return shell.model_selected == alternate and shell.creator_payload == pre.catalog.character_models[alternate].default_payload,
		"switch resets incompatible options"): quit(1); return
	await press(character_model_id.capitalize())
	if not await wait_until(func(): return shell.model_selected == character_model_id and shell.creator_payload == pre.catalog.character_models[character_model_id].default_payload,
		"switch restores original model defaults"): quit(1); return
	# Keyboard focus uses the same candidate preview as pointer hover.
	shell.model_buttons[character_model_id].grab_focus()
	await process_frame
	check(shell.hovered_model == character_model_id, "keyboard focus highlights candidate")
	await press("Customize")
	if not await wait_until(func(): return shell.creator_stage == "FINE" and shell.creator_name_edit != null,
		"fine appearance form is ready"): quit(1); return
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
	var profiles = preload("res://tests/mmo/replica_check.gd")
	var own_physics := profiles.physics(chosen.character_model_id)
	check(client.world_replica.local_player().physics == profiles.binding(chosen.character_model_id), "owner server-selected binding")
	check(remote.physics == profiles.binding(remote.character.appearance_payload.character_model_id), "peer server-selected binding")
	check(world.platform._movement.mass_g == own_physics.body.mass_g and world.platform._movement.top_speed_mm_s == own_physics.motor.top_speed_mm_s, "native predictor uses own mass/motor")
	check(not client.world_replica.latest_frame_sample(remote_id).has("physics"), "20-Hz frame omits static profiles")

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
	if not await verify_peer_push(world,remote_id): quit(1); return
	if not await verify_yuna_pushes_kotone(world,remote_id): quit(1); return
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
	check(client.world_replica.local_player().physics == profiles.binding(chosen.character_model_id), "re-entry keeps selected body/motor binding")
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
	print("LOBBY09_RESULT ", JSON.stringify({"role": role, "checks": checks, "passed": not failed,
		"display_backend": DisplayServer.get_name(), "remote_idle": remote_idle_results,
		"remote_onset": remote_onset_results,"contact":contact_results,"owner_ux":owner_ux_results}))
	quit(1 if failed else 0)
