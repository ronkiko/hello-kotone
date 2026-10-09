extends SceneTree
## Explicit applied-control boundary correlation; independent local ordinals.
const Fixtures = preload("res://tests/mmo/replica_check.gd")
var RULES = Fixtures.rules()
const DT := 1.0/60.0
var checks := 0
var failures: Array = []
var platform: Node
var client: Node
class Driver extends Node:
	var suite: SceneTree
	func _physics_process(_delta: float) -> void:
		set_physics_process(false)
		suite.run()
func _initialize() -> void:
	boot.call_deferred()
func boot() -> void:
	client = root.get_node("MmoClient")
	client.set_process(false)
	platform = load("res://scripts/presentation/platform_world.gd").new()
	root.add_child(platform)
	platform.set_process(false)
	platform.set_physics_process(false)
	platform.set_movement_rules({"movement":RULES})
	var p := Fixtures.player()
	platform.project(Fixtures.MAP,{"map":{"map_id":Fixtures.MAP.map_id,"content_version":1,"content_hash":Fixtures.MAP.content_hash},
		"players":{"p1":p},"local_player_id":"p1","confirmed_local_position_mm":50000})
	var driver := Driver.new()
	driver.suite = self
	root.add_child(driver)
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func sample(tick: int,seq: int,start: int,x: int,v: int = 0,contacts: Array = []) -> Dictionary:
	return {"simulation_tick":tick,"last_applied_control_seq":seq,"control_started_tick":start,
		"position_mm":x,"velocity_mm_s":v,"facing":1,"contacts":contacts}
func reset() -> void:
	client._clear_session()
	client.state = "READY"
	client._world_rules = {"movement":RULES}
	platform._prediction_fenced = false
	platform._resync_requested = false
	platform._apply_authoritative_motion(sample(9000,0,0,50000),true)
func steps(count: int) -> void:
	for _i in range(count): platform._physics_process(DT)
func sent(seq: int,drive: int) -> void:
	client._desired_input = {"drive":drive,"facing":1}
	client.control_sent.emit({"control_seq":seq,"drive":drive,"facing":1})
func run() -> void:
	check(Engine.is_in_physics_frame(),"native integration runs on physics callback")
	reset()
	check(platform._prediction_ordinal == 0,"snapshot resets local ordinal independently of tick9000")
	sent(1,1)
	steps(4)
	check(platform._prediction_history.size()==4,"every local held interval recorded")
	check(platform._prediction_history[0].local_ordinal==1,"local ordinal does not inherit server origin")
	var before: float = platform.character_root.position.x
	platform._apply_authoritative_motion(sample(9501,1,9500,50006,266),false)
	check(platform._prediction_history.size()==2,"explicit seq boundary maps two applied intervals despite server ahead500")
	check(absf(platform.character_root.position.x-before)*125.0<=2,"expected transport lead is not positional divergence")
	check(platform._prediction_ordinal==4,"server marker cannot advance local clock")
	check(not client.prediction_control_state().has("control_seq"),"unsent controls have no speculative network sequence")
	reset()
	sent(1,1)
	steps(5)
	sent(2,0)
	steps(2)
	before=platform.character_root.position.x
	platform._apply_authoritative_motion(sample(9008,1,9001,50100,1000),false)
	check(platform._correction_class=="pending_control" and platform.character_root.position.x==before,
		"old held sample cannot confirm delayed local release")
	check(platform._prediction_history.size()==7,"unapplied release remains in its local ledger")
	platform._apply_authoritative_motion(sample(9010,2,9010,50053,533),false)
	check(platform._prediction_history.size()==1 and platform._prediction_history[0].drive==0,
		"release boundary retires only correlated local interval")
	reset()
	sent(1,1)
	steps(2)
	client._desired_input={"drive":0,"facing":1}
	steps(1)
	client._desired_input={"drive":1,"facing":1}
	steps(1)
	platform._apply_authoritative_motion(sample(9301,1,9300,50006,266),false)
	check(platform._prediction_history.size()==2 and platform._prediction_history[0].drive==0
		and platform._prediction_history[1].drive==1,"coalesced stop occupies its actual local interval once")
	platform._apply_authoritative_motion(sample(9303,1,9300,50022,533),false)
	check(platform._prediction_history.is_empty(),"same applied control ages out coalesced state without ghost replay")
	reset()
	sent(1,1)
	steps(2)
	sent(2,0)
	client._server_input_seq=1
	client.input_rejected.emit("RATE_LIMITED")
	check(not platform._control_ledger.has(2),"definite rejection removes an unapplied control boundary")
	reset()
	steps(40)
	check(platform._prediction_history.size()==40 and not platform._prediction_fenced,"40 interval ceiling")
	steps(1)
	check(platform._prediction_fenced and platform._prediction_history.is_empty(),"41st interval fences and resyncs")
	reset()
	steps(1)
	platform._prediction_history[0].at_ms=Time.get_ticks_msec()-2001
	steps(1)
	check(platform._prediction_fenced,"2s age ceiling")
	reset()
	platform._apply_authoritative_motion(sample(9001,9,9001,50000),false)
	check(platform._prediction_fenced,"unknown applied sequence fails closed")
	reset()
	sent(1,1)
	steps(3)
	platform.set_suspended(true)
	client._clear_session()
	client.state="READY"
	platform.set_suspended(false)
	platform._apply_authoritative_motion(sample(40000,0,0,50000),true)
	steps(1)
	check(platform._prediction_ordinal==1 and platform._prediction_history[0].drive==0
		and platform._control_ledger.size()==1,"fresh epoch clears all old clock/control mappings")
	reset()
	platform._apply_authoritative_motion(sample(8999,0,0,50000),false)
	check(platform._prediction_fenced,"server freshness marker remains independently fenced")
	reset()
	var fast := Fixtures.player()
	fast.physics = Fixtures.binding("yuna")
	fast.character.appearance_payload = {"character_model_id":"yuna","body_variant_id":"standard","face_style_id":"soft","hair_style_id":"bob","hair_color_id":"rose"}
	platform.project(Fixtures.MAP,{"epoch":"profile-lead","map":{"map_id":Fixtures.MAP.map_id,"content_version":1,"content_hash":Fixtures.MAP.content_hash},
		"players":{"p1":fast},"local_player_id":"p1","confirmed_local_position_mm":50000})
	reset()
	sent(1,-1)
	steps(25)
	var held_x: int = platform._pixel_to_server_mm(platform.character_root.position.x)
	platform._apply_authoritative_motion(sample(9119,1,9100,held_x+350,-4200),false)
	check(platform._control_ledger[1].lead_ticks == 5, "held boundary measured five-tick lead")
	sent(2,0)
	steps(5)
	var prior_render: float = platform.character_root.position.x+platform.visual_layer.position.x
	var release_x: int = platform._pixel_to_server_mm(platform.character_root.position.x)
	platform._apply_authoritative_motion(sample(9124,2,9121,release_x+337,-3453),false)
	check(platform._control_ledger[2].lead_ticks == 1, "release boundary independently measured one-tick lead")
	check(platform._correction_class == "blend", "Yuna 280-mm bounded lead change blends within profile's 100-ms travel budget")
	check(absf(platform.character_root.position.x+platform.visual_layer.position.x-prior_render) < 0.001,
		"profile lead transition cannot reverse the rendered root")
	var reverse_steps := 0
	for interval in range(30):
		var before_release: float = platform.character_root.position.x+platform.visual_layer.position.x
		platform._physics_process(DT)
		platform._process(DT)
		if platform.character_root.position.x+platform.visual_layer.position.x > before_release+0.0008: reverse_steps += 1
	check(reverse_steps == 0, "profile-dependent release correction converges without backward render steps")
	sent(3,-1)
	steps(1)
	var response := sample(9200,3,9200,platform._pixel_to_server_mm(platform.character_root.position.x)+337)
	response.contacts = ["p2"]
	response.merge({"contact_delta_velocity_mm_s":8400,"contact_response_tick":9200,"contact_response_facing":1,"contact_response_contacts":["p2"]})
	platform._apply_authoritative_motion(response,false)
	check(platform._correction_class == "snap", "current physical contact stays an authority barrier inside profile blend budget")

	reset()
	# A rebase can leave a subpixel presentation lead after the physical body
	# has already stopped. The blend must not spend that residue backwards.
	platform.visual_layer.position.x = 0.12
	platform._blend_remaining = DT
	platform._blend_start_offset_x = 0.12 * (0.1 / DT)
	var stopped_render := platform.character_root.position.x + platform.visual_layer.position.x
	platform._physics_process(DT)
	check(is_equal_approx(platform.character_root.position.x + platform.visual_layer.position.x, stopped_render),
		"stopped body defers presentation residue instead of reversing")
	client._desired_input = {"drive":1,"facing":1}
	var before_absorb := platform.character_root.position.x + platform.visual_layer.position.x
	platform._physics_process(DT)
	check(platform.character_root.position.x + platform.visual_layer.position.x >= before_absorb - 0.000001
		and absf(platform.visual_layer.position.x) < 0.12,
		"later forward motion absorbs deferred residue monotonically")

	reset()
	var owner := Fixtures.player()
	var peer := owner.duplicate(true)
	peer.player_id="p2"
	peer.nickname="peer"
	peer.character.character_id="p2"
	peer.character.display_name="peer"
	peer.character.appearance_payload = {"character_model_id":"yuna","body_variant_id":"standard",
		"face_style_id":"soft","hair_style_id":"bob","hair_color_id":"rose"}
	peer.physics = Fixtures.binding("yuna")
	peer.motion.position_mm=50450
	platform.project(Fixtures.MAP,{"epoch":"e1","map":{"map_id":Fixtures.MAP.map_id,"content_version":1,"content_hash":Fixtures.MAP.content_hash},
		"players":{"p1":owner,"p2":peer},"local_player_id":"p1","confirmed_local_position_mm":50000})
	platform._update_peer_proxies(0.0)
	await physics_frame
	await physics_frame
	sent(1,1)
	steps(20)
	var owner_body: Dictionary = Fixtures.physics("kotone").body
	var peer_body: Dictionary = Fixtures.physics("yuna").body
	var contact_center := int(peer.motion.position_mm) - int((int(owner_body.collision_width_mm) + int(peer_body.collision_width_mm)) / 2)
	check(platform._peer_proxies.has("p2") and platform._predicted_contacts.has("p2"),"native mixed-profile peer proxy predicts physical collision")
	var proxy_shape: CollisionShape2D = platform._peer_proxies.p2.get_child(0)
	check(is_equal_approx(proxy_shape.shape.size.x,2.88) and is_equal_approx(proxy_shape.shape.size.y,12.4)
		and is_equal_approx(proxy_shape.position.x,0.0) and is_equal_approx(proxy_shape.position.y,-6.2),
		"Yuna proxy uses her selected 360x1550-mm body")
	check(platform._pixel_to_server_mm(platform.character_root.position.x)<=contact_center+1,
		"owner cannot predict through narrower Yuna collider")
	platform.remote_players.p2.timeline._samples.back().received_usec=Time.get_ticks_usec()-250000
	platform._update_peer_proxies(0.0)
	check(platform._peer_proxies.p2.collision_layer==0,"stale hint disables ghost collider after200ms")
	platform._remove_remote("p2")
	check(platform._peer_proxies.is_empty(),"peer leave removes proxy state")
	client._clear_session()
	platform.queue_free()
	print(JSON.stringify({"suite":"owner-prediction","checks":checks,"failures":failures,
		"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
