extends SceneTree
const Prediction = preload("res://scripts/presentation/local_prediction.gd")
const Trajectory = preload("res://scripts/presentation/local_trajectory.gd")
const Profile = preload("res://scripts/presentation/player_motion.gd")
var checks := 0
var failures: Array[String] = []
var document := {"schema_version":1,"map_id":"city/apartment","content_version":1,"min_x":0,"max_x":100,"spawn_x":50,
	"units_per_meter":1,"content_hash":"4f465435cbb8eb3e5154a4776be29e7aee4f73376e00fb26299bfbf0cfcd361b"}

func _initialize() -> void:
	start.call_deferred()

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures.append(reason)

func replica(x: int, status: String = "SYNCED") -> Dictionary:
	return {"status":status,"reconnect_required":status != "SYNCED","epoch":"e1",
		"map":{"map_id":document.map_id,"content_version":1,"content_hash":document.content_hash},
		"local_player_id":"p1","confirmed_local_x":x}

func start() -> void:
	var model := Prediction.new()
	check(model.observe(document,replica(50),1), "OBSERVE_BASELINE")
	check(model.accept_input(1,"right",50), "ACCEPT_RIGHT_INPUT_SEQUENCE")
	check(model.authoritative_step(51) == 0.0, "MATCHED_STEP_NEEDS_NO_CORRECTION")
	check(model.authoritative_step(51, true) == 0.0, "SERVER_HOLD_REBASES_WITHOUT_DELTA")
	check(model.authoritative_step(52) == 0.0, "RESUME_AFTER_HOLD_RESTARTS_FROM_AUTHORITATIVE_BASELINE")
	check(model.accept_input(2,"stop",51), "STOP_SEQUENCE_BASELINE")
	check(model.authoritative_step(51) == 0.0, "STOP_HAS_NO_NOMINAL_STEP")
	check(not model.accept_input(0,"right",51) and not model.accept_input(3,"up",51), "INVALID_INPUT_MODEL_REJECTED")

	var stale := replica(51,"STALE")
	check(model.observe(document,stale,1) and not model.view().healthy and not model.view().active, "STALE_CLEARS_ACTIVE_RECONCILIATION")
	check(model.observe(document,replica(51),1), "HEALTHY_REOPENS_MODEL")
	check(model.accept_input(1,"left",51), "FRESH_STREAM_SEQUENCE_MODEL")
	check(model.authoritative_step(50) == 0.0, "LEFT_EXPECTED_STEP")

	var profile := Profile.new()
	profile.configure(1,200,1,8.0)
	var trajectory := Trajectory.new()
	trajectory.configure(profile,32.0,832.0)
	trajectory.reset(432.0)
	trajectory.set_intent(1)
	var first := trajectory.advance(.2)
	check(is_equal_approx(first.after,440.0) and is_equal_approx(trajectory.model_x,440.0), "CLIENT_ADVANCES_ONE_UNIT_WITHOUT_ACK")
	var second := trajectory.advance(.2)
	check(is_equal_approx(second.after,448.0), "CLIENT_CONTINUES_PAST_ONE_STEP_WITH_HELD_INPUT")
	trajectory.set_authoritative_hold(true)
	trajectory.correct_to(440.0)
	check(is_equal_approx(trajectory.model_x,440.0) and is_equal_approx(trajectory.visual_x,448.0), "AUTHORITATIVE_HOLD_MOVES_MODEL_ONLY")
	var magnetic := trajectory.advance(.025)
	check(magnetic.after < 448.0 and magnetic.after > 440.0, "RENDER_MAGNETS_TOWARD_HELD_MODEL")
	trajectory.advance(1)
	check(is_equal_approx(trajectory.visual_x,trajectory.model_x), "MAGNET_SETTLES")
	var held_model := trajectory.model_x
	trajectory.advance(1)
	check(trajectory.model_x == held_model, "HELD_MODEL_DOES_NOT_PREDICT_FORWARD")
	trajectory.set_authoritative_hold(false)
	trajectory.advance(.2)
	check(trajectory.model_x > held_model, "RELEASED_HOLD_RESUMES_LOCAL_PREDICTION")
	trajectory.set_intent(0)
	var stopped_model := trajectory.model_x
	trajectory.advance(1)
	check(is_equal_approx(trajectory.model_x,stopped_model), "RELEASE_STOPS_LOCAL_SIMULATION")

	print(JSON.stringify({"suite":"prediction","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
