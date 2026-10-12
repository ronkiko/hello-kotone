extends SceneTree

const Timeline = preload("res://scripts/presentation/remote_motion_timeline.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func motion(tick: int, position_mm: int, velocity_mm_s: int, contacts: Array = [], facing: int = 1,
		response_delta: int = 0, response_facing: int = 0, response_tick: int = 0,
		response_contacts: Array = [], impact_sources: Array = []) -> Dictionary:
	return {"realm_tick": tick, "position_mm": position_mm,
		"velocity_mm_s": velocity_mm_s, "facing": facing, "contacts": contacts,
		"contact_delta_velocity_mm_s": response_delta, "contact_response_facing": response_facing,
		"contact_response_tick": response_tick, "contact_response_contacts": response_contacts,
		"contact_impact_sources": impact_sources}

func close_to(actual: float, expected: float, epsilon: float = 0.01) -> bool:
	return absf(actual - expected) <= epsilon

func _initialize() -> void:
	var timeline := Timeline.new()
	check(timeline.push_sample("e1|city/apartment|1", motion(0, 1000, 1000), 0, 1000) == "seeded",
		"join seeds a sufficient immediate sample")
	check(close_to(float(timeline.sample_at(0).position_mm), 1000.0), "initial sample is visible without a warmup wait")
	check(timeline.push_sample("e1|city/apartment|1", motion(3, 1050, 1000), 50000, 1000) == "accepted",
		"monotonic authoritative sample accepted")
	check(close_to(float(timeline.sample_at(125000).position_mm), 1025.0),
		"100 ms delayed server timeline interpolates between samples")
	check(close_to(float(timeline.sample_at(150000).position_mm), 1050.0),
		"buffer catches up to the latest sample on the same server tick")
	check(timeline.push_sample("e1|city/apartment|1", motion(3, 9999, 0), 60000, 1000) == "ignored",
		"duplicate simulation tick cannot roll the remote backward")
	check(timeline.push_sample("e1|city/apartment|1", motion(2, 2000, 0), 60000, 1000) == "ignored",
		"older simulation tick is ignored")
	check(close_to(float(timeline.sample_at(150000).position_mm), 1050.0), "duplicate and stale samples leave the timeline unchanged")
	var jitter := Timeline.new()
	jitter.push_sample("e1|city/apartment|1", motion(0, 0, 1000), 0, 1000)
	jitter.push_sample("e1|city/apartment|1", motion(3, 50, 1000), 50000, 1000)
	var before_late_frame: Dictionary = jitter.sample_at(175000)
	jitter.push_sample("e1|city/apartment|1", motion(6, 100, 1000), 200000, 1000)
	var after_late_frame: Dictionary = jitter.sample_at(200000)
	check(close_to(float(before_late_frame.position_mm), 75.0)
		and close_to(float(after_late_frame.position_mm), float(before_late_frame.position_mm)),
		"late frame arrival cannot rewind the render cursor")

	for tick in range(6, 36, 3):
		var offset := int(tick / 3) * 50
		timeline.push_sample("e1|city/apartment|1", motion(tick, 1000 + offset, 1000), tick * 1000000 / 60, 1000)
	check(timeline.sample_count() == 8 and int(timeline.metrics().sample_peak) == 8,
		"recent sample ring stays bounded at eight")
	var response := Timeline.new()
	response.push_sample("e1|city/apartment|1", motion(0, 1000, 0), 0, 3000)
	response.push_sample("e1|city/apartment|1", motion(3, 1000, 0, [], 1, 1200, 1, 2, ["p2"], ["p2"]), 50000, 3000)
	var before_response: Dictionary = response.sample_at(116667)
	var at_response: Dictionary = response.sample_at(133334)
	check(int(before_response.contact_delta_velocity_mm_s) == 0
		and int(at_response.contact_delta_velocity_mm_s) == 1200
		and int(at_response.contact_response_tick) == 2
		and at_response.contact_response_contacts == ["p2"]
		and at_response.contact_impact_sources == ["p2"],
		"contact response is presented once its server tick enters the delayed cursor")

	var rebased := Timeline.new()
	rebased.push_sample("e1|city/apartment|1", motion(9, 1000, 0), 150000, 1820)
	rebased.push_sample("e1|city/apartment|1", motion(12, 1000, 758, ["p2"], 1, 758, 1, 12, ["p2"], ["p2"]), 200000, 1820)
	check(rebased.sample_at(200000).contact_response_tick == 0, "received response waits for delayed server cursor")
	check(rebased.push_sample("e1|city/apartment|1", motion(15, 1400, 7800), 250000, 1820) == "reset", "separation rebases position before delayed contact reaction")
	check(rebased.sample_at(250000).contact_response_tick == 0, "rebase cannot present future causal fact")
	check(rebased.sample_at(300000).contact_response_tick == 12, "received response survives contact separation reset")
	check(rebased.sample_at(300000).contact_delta_velocity_mm_s == 758, "mass-aware physical response retained intact")
	rebased.push_sample("e1|city/apartment|1", motion(18, 9999, 0), 300000, 1820)
	check(rebased.sample_at(350000).contact_response_tick == 12, "same-scope discontinuity retains authoritative response")
	for tick in range(21, 81, 3):
		rebased.push_sample("e1|city/apartment|1", motion(tick, 10000, 0, [], 1, 758, 1, tick, ["p2"], ["p2"]), tick*1000000/60, 1820)
	check(rebased._responses.size() == 8 and rebased.sample_count() <= 8, "causal and motion rings independently bounded")
	rebased.push_sample("e2|city/apartment|1", motion(0, 2000, 0), 1500000, 1820)
	check(rebased._responses.is_empty() and rebased.sample_at(1600000).contact_response_tick == 0, "fresh scope clears pending responses")

	var stale := Timeline.new()
	stale.push_sample("e1|city/apartment|1", motion(0, 0, 1000), 0, 1000)
	var stale_state: Dictionary = stale.sample_at(250000)
	check(close_to(float(stale_state.position_mm), 100.0) and stale_state.frozen and stale_state.velocity_mm_s == 0,
		"stale stream extrapolates for at most 100 ms then freezes")
	check(int(stale.metrics().extrapolated) == 1 and int(stale.metrics().frozen) == 1,
		"sample diagnostics count bounded extrapolation and freeze observations")

	var timing := Timeline.new()
	var ages := [9, 100, 3]
	var clocks := [1000000, 1100000, 1103000]
	for index in range(ages.size()):
		var now_usec: int = clocks[index]
		var received_usec: int = now_usec - int(ages[index]) * 1000
		check(timing.push_sample("e1|city/apartment|1", motion(60 + index, 1000, 0),
			received_usec, 1000) in ["seeded", "accepted"], "local receive sample accepted %d" % index)
		timing.sample_at(now_usec)
	var age_metrics: Dictionary = timing.metrics().sample_age_ms
	var interpolation_metrics: Dictionary = timing.metrics().interpolation_age_ms
	check(age_metrics.count == 3 and close_to(age_metrics.p50, 9.0)
		and close_to(age_metrics.p95, 100.0) and close_to(age_metrics.max, 100.0)
		and close_to(age_metrics.latest, 3.0), "sample age uses local receive clock and latest-by-arrival")
	check(interpolation_metrics.count == 3 and close_to(interpolation_metrics.p50, 16.6667)
		and close_to(interpolation_metrics.p95, 91.0) and close_to(interpolation_metrics.max, 91.0)
		and close_to(interpolation_metrics.latest, 16.6667),
		"interpolation age uses local render cursor with millisecond units")
	timing._sample_age_window.clear()
	timing._interpolation_age_window.clear()
	for value in range(257):
		timing._record_window(timing._sample_age_window, float(value))
		timing._record_window(timing._interpolation_age_window, float(value))
	var rolled: Dictionary = timing.metrics().sample_age_ms
	check(timing._sample_age_window.size() == 256 and timing._sample_age_window.front() == 1.0
		and rolled.count == 256 and rolled.p50 == 128.0 and rolled.p95 == 244.0
		and rolled.max == 256.0 and rolled.latest == 256.0,
		"age windows evict exactly their oldest value at the 256-sample cap")
	timing.reset()
	check(timing.metrics().sample_age_ms.count == 0 and timing.metrics().interpolation_age_ms.count == 0,
		"timeline reset clears both rolling age windows")
	timing._record_window(timing._sample_age_window, 77.0)
	timing.push_sample("e2|city/apartment|1", motion(0, 1000, 0), 1200000, 1000)
	timing.sample_at(1203000)
	check(timing.metrics().sample_age_ms.count == 1 and timing.metrics().sample_age_ms.latest == 3.0,
		"scope barrier clears old age samples before recording the new scope")

	var distance_limited := Timeline.new()
	distance_limited.push_sample("e1|city/apartment|1", motion(0, 0, 3000), 0, 3000)
	var distance_state: Dictionary = distance_limited.sample_at(200000)
	check(close_to(float(distance_state.position_mm), 250.0) and distance_state.frozen,
		"extrapolation is capped at 250 mm even below the time ceiling")

	var contact := Timeline.new()
	contact.push_sample("e1|city/apartment|1", motion(0, 4000, 3000), 0, 3000)
	check(contact.push_sample("e1|city/apartment|1", motion(3, 4150, 0, ["p2"]), 50000, 3000) == "reset",
		"contact transition is an authoritative interpolation barrier")
	check(close_to(float(contact.sample_at(50000).position_mm), 4150.0),
		"contact transition presents the committed contact position")
	var left := Timeline.new()
	var right := Timeline.new()
	left.push_sample("e1|city/apartment|1", motion(0, 4000, 3000), 0, 3000)
	right.push_sample("e1|city/apartment|1", motion(0, 4600, -3000), 0, 3000)
	left.push_sample("e1|city/apartment|1", motion(3, 4150, 0, ["p2"]), 50000, 3000)
	right.push_sample("e1|city/apartment|1", motion(3, 4550, 0, ["p1"]), 50000, 3000)
	var left_at_contact: Dictionary = left.sample_at(50000)
	var right_at_contact: Dictionary = right.sample_at(50000)
	check(float(right_at_contact.position_mm) - float(left_at_contact.position_mm) >= 400.0,
		"atomic peer contact samples do not interpolate through body penetration")

	var teleport := Timeline.new()
	teleport.push_sample("e1|city/apartment|1", motion(0, 1000, 0), 0, 3000)
	check(teleport.push_sample("e1|city/apartment|1", motion(3, 5000, 0), 50000, 3000) == "reset",
		"large correction resets as teleport/discontinuity")
	check(close_to(float(teleport.sample_at(50000).position_mm), 5000.0), "discontinuity never blends from the old position")
	check(teleport.push_sample("e2|city/apartment|1", motion(0, 2000, 0), 60000, 3000) == "seeded",
		"epoch change clears the old timeline")
	check(close_to(float(teleport.sample_at(60000).position_mm), 2000.0), "new epoch starts at its own sample")

	print(JSON.stringify({"suite":"remote-motion-timeline","checks":checks,
		"failures":failures,"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
