extends SceneTree
const Prediction = preload("res://scripts/presentation/local_prediction.gd")
const Replica = preload("res://scripts/mmo/world_replica.gd")
const Platform = preload("res://scripts/presentation/platform_world.gd")
var checks := 0
var failures: Array[String] = []
var document := {"schema_version":1,"map_id":"city/apartment","content_version":1,"min_x":0,"max_x":100,"spawn_x":50,"units_per_meter":1,"content_hash":"4f465435cbb8eb3e5154a4776be29e7aee4f73376e00fb26299bfbf0cfcd361b"}
var player := {"player_id":"p1","nickname":"player1","zone_id":"city/apartment","x":50}
var replica := Replica.new()
var prediction := Prediction.new()
var local_facts := 0

func _initialize() -> void:
	start.call_deferred()

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures.append(reason)

func event(revision: int, who: Dictionary, kind: String = "moved") -> Dictionary:
	return {"protocol_version":4,"type":"event","event":kind,"epoch":"e1","zone_id":"city/apartment","revision":revision,"data":{"player":who}}

func start() -> void:
	check(not prediction.begin("right"), "EMPTY_CANNOT_PREDICT")
	var baseline := {"epoch":"e1","revision":1,"map":{"map_id":document.map_id,"content_version":1,"content_hash":document.content_hash},"players":[player]}
	check(replica.start(baseline,"p1","player1") and replica.install_map(document), "BASELINE")
	replica.changed.connect(func(): prediction.observe(document,replica.view(),1))
	replica.local_moved.connect(func():
		local_facts += 1
		prediction.reconcile())
	check(prediction.observe(document,replica.view(),1), "OBSERVE_VALIDATED_PAIR")
	var before := replica.snapshot()
	check(not prediction.begin("up") and prediction.begin("right"), "DIRECTION_ONLY")
	check(prediction.view().confirmed_x == 50 and prediction.view().predicted_x == 51 and prediction.view().target_x == 51, "THREE_POSITIONS_SEPARATE")
	var all_refused := true
	for i in range(1000): all_refused = not prediction.begin("left") and all_refused
	check(all_refused and prediction.view().predicted_x == 51 and replica.snapshot() == before, "ONE_STEP_NO_QUEUE_NO_FACT_WRITE")
	var copy := prediction.view()
	copy.target_x = -99999
	check(prediction.view().target_x == 51, "DEFENSIVE_VIEW")
	var remote := {"player_id":"p2","nickname":"player2","zone_id":"city/apartment","x":52}
	check(replica.apply_event(event(2,remote,"joined")), "REMOTE_JOIN")
	remote.x = 53
	check(replica.apply_event(event(3,remote)) and prediction.view().active and prediction.view().target_x == 51 and local_facts == 0, "REMOTE_FACT_PRESERVES_SPECULATION")
	player.x = 51
	check(replica.apply_event(event(4,player)) and not prediction.view().active and prediction.view().predicted_x == null and prediction.view().target_x == 51 and local_facts == 1, "OWN_FACT_RECONCILES_ONCE")
	check(prediction.begin("right"), "NEXT_SINGLE_STEP")
	player.x = 49
	check(replica.apply_event(event(5,player)) and prediction.view().target_x == 49 and not prediction.view().active, "SERVER_CORRECTION_OVERRIDES_PREDICTION")
	check(prediction.begin("right"), "BEGIN_BEFORE_UNCHANGED_FACT")
	check(replica.apply_event(event(6,player)) and not prediction.view().active and local_facts == 3, "UNCHANGED_OWN_FACT_RESOLVES_SPECULATION")
	check(prediction.begin("left"), "BEGIN_BEFORE_REJECTION")
	prediction.reconcile()
	check(prediction.view().target_x == 49 and prediction.view().healthy and replica.local_player().x == 49, "REJECTION_ROLLBACK_NO_AUTHORITY_WRITE")
	check(prediction.begin("right"), "BEGIN_BEFORE_RESYNC")
	replica.begin_resync()
	check(not prediction.view().active and not prediction.begin("right") and prediction.view().target_x == 49, "RESYNC_CLEARS_AND_BLOCKS_PREDICTION")
	check(replica.replace_snapshot(replica.snapshot()) and prediction.begin("right"), "HEALTHY_STATE_REOPENS")
	replica.invalidate("DISCONNECTED")
	check(not prediction.view().active and not prediction.begin("left") and prediction.view().target_x == 49, "FENCING_RETAINS_ONLY_LAST_FACT")
	replica.clear()
	baseline.epoch = "e2"
	baseline.players = [{"player_id":"p1","nickname":"player1","zone_id":"city/apartment","x":0}]
	check(replica.start(baseline,"p1","player1") and replica.install_map(document), "FRESH_EPOCH_BASELINE")
	check(prediction.begin("left") and prediction.view().target_x == 0, "LEFT_PREDICTION_CLAMP")
	prediction.reconcile()
	var max_view := replica.view()
	max_view.confirmed_local_x = 100
	check(prediction.observe(document,max_view,1) and prediction.begin("right") and prediction.view().target_x == 100, "RIGHT_PREDICTION_CLAMP")
	check(not prediction.observe(document,max_view,2) and prediction.view().target_x == null and not prediction.begin("right"), "INVALID_RULES_CLEAR")
	check(prediction.observe(document,replica.view(),1), "RESTORE_VALID_FACTS")
	var wrong := document.duplicate(true)
	wrong.content_hash = "0".repeat(64)
	check(not prediction.observe(wrong,replica.view(),1) and not prediction.begin("right"), "MISMATCHED_MAP_BLOCKS")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(458,116)
	root.add_child(viewport)
	var platform := Platform.new()
	viewport.add_child(platform)
	platform.set_process(false)
	var view := replica.view()
	view.confirmed_local_x = 50
	check(platform.project(document,view), "PRESENTER_BASELINE")
	check(platform.project(document,view,51) and platform.sprite.position.x == 432 and view.confirmed_local_x == 50, "SPECULATIVE_TARGET_NO_SNAP_NO_MUTATION")
	platform._process(.02)
	check(platform.sprite.position.x > 432 and platform.sprite.position.x < 440, "RENDER_BETWEEN_CONFIRMED_AND_PREDICTED")
	platform._resize_projection()
	platform._process(.1)
	check(platform.sprite.position.x == 440, "RESIZE_RETAINS_DISPLAY_TARGET")
	platform.sprite.position.x = -99999
	platform._process(0)
	check(platform.sprite.position.x == 440, "TAMPER_CANNOT_REWRITE_RENDER_MODEL")
	check(platform.project(document,view), "RECONCILE_CONFIRMED_TARGET")
	platform._process(.02)
	check(platform.sprite.position.x > 432 and platform.sprite.position.x < 440 and platform.sprite.texture == platform.WALK_LEFT, "BOUNDED_SMOOTH_ROLLBACK")
	platform._process(1)
	check(platform.sprite.position.x == 432 and view.confirmed_local_x == 50, "ROLLBACK_COMPLETES_NO_FACT_WRITE")
	check(not platform.project(document,view,-1) and not platform.project(document,view,101) and not platform.project(document,view,51.0), "INVALID_DISPLAY_TARGETS_REJECTED")
	view.confirmed_local_x = 100
	platform.project(document,view,100)
	platform._process(1000)
	check(platform.sprite.position.x == 832, "LARGE_DELTA_STAYS_IN_BOUNDS")
	viewport.queue_free()
	print(JSON.stringify({"suite":"prediction","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
