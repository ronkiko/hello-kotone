extends SceneTree
## Independent server/local clocks and fixed one-way delivery; shipped predictor.
const Fixtures = preload("res://tests/mmo/replica_check.gd")
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
var RULES = Fixtures.rules()
const DT = 1.0 / 60.0
var platform: Node
var client: Node
var results: Array = []
var checks := 0
var failures: Array = []
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
	var player := Fixtures.player()
	platform.project(Fixtures.MAP, {"map":{"map_id":Fixtures.MAP.map_id,"content_version":1,"content_hash":Fixtures.MAP.content_hash},
		"players":{"p1":player},"local_player_id":"p1","confirmed_local_position_mm":50000})
	var driver := Driver.new()
	driver.suite = self
	root.add_child(driver)
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func run() -> void:
	for model in ["kotone", "yuna"]:
		for direction in [-1, 1]:
			for delay in [0, 3, 6]:
				for release_phase in [-1,0,1]:
					for nearby_peer in [false,true]:
						scenario(model, direction, delay,release_phase,nearby_peer)
				scenario(model,direction,delay,0,false,true)
	print(JSON.stringify({"suite":"owner-motion-ux","checks":checks,"failures":failures,"scenarios":results,
		"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
func scenario(model: String, direction: int, delay: int,release_phase: int,nearby_peer: bool,slow_server: bool=false) -> void:
	client._clear_session()
	client.state = "READY"
	client._world_rules = {"movement":RULES}
	platform._prediction_fenced = false
	platform._resync_requested = false
	var player := Fixtures.player()
	player.character.appearance_payload={"character_model_id":model,"body_variant_id":"standard","face_style_id":"soft",
		"hair_style_id":"short" if model=="kotone" else "bob","hair_color_id":"chestnut" if model=="kotone" else "rose"}
	player.physics = Fixtures.binding(model)
	var players := {"p1":player}
	if nearby_peer:
		var peer := player.duplicate(true)
		peer.player_id="p2"
		peer.nickname="nearby"
		peer.character.character_id="p2"
		peer.character.display_name="nearby"
		peer.motion.position_mm=50000-direction*500
		players.p2=peer
	platform.project(Fixtures.MAP,{"epoch":"ux","map":{"map_id":Fixtures.MAP.map_id,"content_version":1,"content_hash":Fixtures.MAP.content_hash},
		"players":players,"local_player_id":"p1","confirmed_local_position_mm":50000})
	platform._local_model_id = model
	Appearance.Library.install(platform.sprite, model)
	platform._gait.reset(platform.sprite, direction)
	var sample := {"simulation_tick":8000,"position_mm":50000,"velocity_mm_s":0,"facing":direction,
		"last_applied_control_seq":0,"control_started_tick":8000,"contacts":[]}
	platform._apply_authoritative_motion(sample, true)
	var server_x := 50000.0
	var server_v := 0.0
	var server_drive := 0
	var server_seq := 0
	var accepted_drive := 0
	var accepted_seq := 0
	var last_physical_tick := -1
	var started_tick := 8000
	var delivery: Array = []
	var trace: Array = []
	var reverse_steps := 0
	var reverse_mm := 0.0
	var idle_during_hold := 0
	var body_reverse_steps := 0
	var camera_reverse_steps := 0
	var before_body: float = platform.character_root.position.x
	var before_camera: float = platform.camera.position.x
	var before: float = platform.character_root.position.x + platform.visual_layer.position.x
	var snaps_before: int = platform.prediction_metrics().snaps
	for ordinal in range(180):
		# Independent phase: server marker starts three ticks ahead of the local clock.
		var server_tick := 8003 + ordinal - (int(ordinal/12) if slow_server else 0)
		if ordinal in [12,72]:
			var drive := direction if ordinal == 12 else 0
			client._desired_input = {"drive":drive,"facing":direction}
			if client.has_signal("control_sent"):
				client.control_sent.emit({"control_seq":1 if ordinal == 12 else 2,"drive":drive,"facing":direction})
		if ordinal == 12 + delay:
			accepted_drive = direction
			accepted_seq = 1
		if ordinal == 72 + delay + release_phase:
			accepted_drive = 0
			accepted_seq = 2
		if server_tick != last_physical_tick:
			if accepted_seq != server_seq:
				started_tick = server_tick
			server_seq = accepted_seq
			server_drive = accepted_drive
			server_v = move_toward(server_v, server_drive * float(Fixtures.physics(model).motor.top_speed_mm_s), float(Fixtures.physics(model).motor.drive_force_mN) * 1000.0 / float(Fixtures.physics(model).body.mass_g) * DT)
			server_x += server_v * DT
			last_physical_tick = server_tick
		if ordinal % 3 == 0:
			delivery.append({"due":ordinal+delay,"sample":{"simulation_tick":server_tick,
				"position_mm":roundi(server_x),"velocity_mm_s":roundi(server_v),"facing":direction,
				"last_applied_control_seq":server_seq,"control_started_tick":started_tick,"contacts":[]}})
		while not delivery.is_empty() and int(delivery[0].due) <= ordinal:
			var arrived: Dictionary = delivery.pop_front().sample
			platform._apply_authoritative_motion(arrived,false)
		platform._physics_process(DT)
		# Three render callbacks per physics interval expose offset-only reverse steps.
		for _render in range(3):
			platform._process(DT/3.0)
			var sub_rendered: float = platform.character_root.position.x+platform.visual_layer.position.x
			var sub_signed := direction*(sub_rendered-before)*(1000.0 / platform.pixels_per_meter)
			if ordinal>=12 and sub_signed < -0.1:
				reverse_steps+=1
				reverse_mm=maxf(reverse_mm,-sub_signed)
			before=sub_rendered
		var rendered: float = platform.character_root.position.x + platform.visual_layer.position.x
		var signed_mm: float = direction * (rendered-before) * 125.0
		if ordinal >= 12 and signed_mm < -0.1:
			reverse_steps += 1
			reverse_mm = maxf(reverse_mm,-signed_mm)
		if ordinal >= 30 and ordinal < 72 and platform.sprite.animation == Appearance.idle_animation(direction):
			idle_during_hold += 1
		# Bounded focused trace includes every test interval, never credentials.
		trace.append({"diagnostics":platform.prediction_diagnostics(),"frame_seq":ordinal/3+1,"local_ms":ordinal*1000.0/60.0,"local_ordinal":ordinal,"server_tick":server_tick,
			"applied_seq":server_seq,"desired_drive":client._desired_input.drive,"server_drive":server_drive,
			"confirmed_mm":roundi(server_x),"body_mm":platform._pixel_to_server_mm(platform.character_root.position.x),
			"render_mm":platform._pixel_to_server_mm(rendered),"offset_px":platform.visual_layer.position.x,
			"contacts":platform._predicted_contacts.duplicate(),"animation":String(platform.sprite.animation),"camera_px":platform.camera.position.x})
		if ordinal >= 12 and direction * (platform.character_root.position.x-before_body) < -0.0008:
			body_reverse_steps += 1
		if ordinal >= 12 and direction * (platform.camera.position.x-before_camera) < -0.0008:
			camera_reverse_steps += 1
		before_body = platform.character_root.position.x
		before_camera = platform.camera.position.x
		before = rendered
	var label := "%s/%d/%dms/phase%d/peer%d/slow%d" % [model,direction,delay*1000/60,release_phase,int(nearby_peer),int(slow_server)]
	var residual: int = absi(platform._pixel_to_server_mm(before)-roundi(server_x))
	results.append({"case":label,"reverse_steps":reverse_steps,"body_reverse_steps":body_reverse_steps,"camera_reverse_steps":camera_reverse_steps,"max_reverse_mm":reverse_mm,
		"idle_during_hold":idle_during_hold,"settled_residual_mm":residual,
		"snaps":platform.prediction_metrics().snaps-snaps_before})
	var output := OS.get_environment("OWNER_UX_OUTPUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output.path_join("%s-%d-%d-%d-%d-%d.json" % [model,direction,delay,release_phase,int(nearby_peer),int(slow_server)]),FileAccess.WRITE)
		file.store_string(JSON.stringify(trace))
	check(camera_reverse_steps == 0,label+" camera never amplifies backward rebase")
	check(platform._peer_proxies.size()==int(nearby_peer),label+" bounded nearby prediction proxies")
	check(reverse_steps == 0,label+" monotonic signed owner render trajectory")
	check(idle_during_hold == 0,label+" continuous hold has no idle flicker")
	check(residual <= 6,label+" settles within 0.05px numerical presentation deadband")
	check(platform.prediction_metrics().snaps == snaps_before,label+" free space has no contact/discontinuity snap")
