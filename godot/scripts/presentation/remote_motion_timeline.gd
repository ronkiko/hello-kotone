extends RefCounted
## Server-tick timeline for one remote character. Never consumes client input.

const MAX_SAMPLES := 8
const Protocol = preload("res://scripts/mmo/protocol_v8.gd")
const SERVER_TICK_HZ := 60.0
const INTERPOLATION_DELAY_TICKS := 6.0
const MAX_EXTRAPOLATION_TICKS := 6.0
const MAX_EXTRAPOLATION_MM := 250.0
const MAX_SAMPLE_GAP_TICKS := 12
const SNAP_CORRECTION_MM := 250.0

var _scope := ""
var _samples: Array[Dictionary] = []
# Causal facts outlive positional contact/discontinuity rebases within one scope.
var _responses: Array[Dictionary] = []
var _latest_response_tick := 0
var _last_render_tick := -1.0
var _metrics := {
	"accepted": 0,
	"duplicates": 0,
	"stale": 0,
	"snaps": 0,
	"extrapolated": 0,
	"frozen": 0,
	"max_extrapolation_ms": 0.0,
	"max_extrapolation_mm": 0.0,
	"sample_peak": 0,
}

func reset() -> void:
	_scope = ""
	_samples.clear()
	_responses.clear()
	_latest_response_tick = 0
	_last_render_tick = -1.0

func sample_count() -> int:
	return _samples.size()

func latest_tick() -> int:
	return int(_samples.back().tick) if not _samples.is_empty() else -1

func latest_position_mm() -> int:
	return int(_samples.back().position_mm) if not _samples.is_empty() else 0

func push_sample(scope: String, motion: Dictionary, received_usec: int, top_speed_mm_s: int) -> String:
	if scope.is_empty() or not motion.has("simulation_tick") or not motion.has("position_mm") \
		or not motion.has("velocity_mm_s") or not motion.has("facing"):
		return "ignored"
	if _scope != scope:
		reset()
		_scope = scope
	var tick: Variant = motion.get("simulation_tick")
	var position: Variant = motion.get("position_mm")
	var velocity: Variant = motion.get("velocity_mm_s")
	var facing: Variant = motion.get("facing")
	var contacts_value: Variant = motion.get("contacts", [])
	var response_delta: Variant = motion.get("contact_delta_velocity_mm_s", 0)
	var response_facing: Variant = motion.get("contact_response_facing", 0)
	var response_tick: Variant = motion.get("contact_response_tick", 0)
	var response_contacts_value: Variant = motion.get("contact_response_contacts", [])
	var impact_sources_value: Variant = motion.get("contact_impact_sources", [])
	if typeof(tick) != TYPE_INT or int(tick) < 0 or typeof(position) != TYPE_INT \
		or typeof(velocity) != TYPE_INT or typeof(facing) != TYPE_INT or int(facing) not in [-1, 1] \
		or not contacts_value is Array or typeof(response_delta) != TYPE_INT \
		or abs(int(response_delta)) > 100000 or typeof(response_facing) != TYPE_INT \
		or int(response_facing) not in [-1, 0, 1] or typeof(response_tick) != TYPE_INT \
		or int(response_tick) < 0 or int(response_tick) > int(tick) \
		or not response_contacts_value is Array or response_contacts_value.size() > 63 \
		or not impact_sources_value is Array or impact_sources_value.size() > 63:
		return "ignored"
	var contacts: Array = contacts_value.duplicate()
	contacts.sort()
	var response_contacts: Array = response_contacts_value.duplicate()
	response_contacts.sort()
	if response_contacts != response_contacts_value:
		return "ignored"
	for contact in response_contacts:
		if not Protocol.token(contact) or contact in ["wall_min", "wall_max"]:
			return "ignored"
	var impact_sources: Array = impact_sources_value.duplicate()
	impact_sources.sort()
	if impact_sources != impact_sources_value:
		return "ignored"
	for source in impact_sources:
		if not Protocol.token(source) or not source in response_contacts:
			return "ignored"
	var has_response := int(response_delta) != 0
	if (not impact_sources.is_empty() and not has_response) \
		or has_response != (not response_contacts.is_empty()) \
		or has_response != (int(response_facing) in [-1, 1]) \
		or has_response != (int(response_tick) > 0):
		return "ignored"
	var next := {"tick": int(tick), "position_mm": int(position),
		"velocity_mm_s": int(velocity), "facing": int(facing),
		"contacts": contacts, "received_usec": received_usec,
		"contact_delta_velocity_mm_s": int(response_delta),
		"contact_response_facing": int(response_facing),
		"contact_response_tick": int(response_tick),
		"contact_response_contacts": response_contacts,
		"contact_impact_sources": impact_sources}
	if _samples.is_empty():
		_append(next)
		_metrics.accepted += 1
		return "seeded"
	var previous: Dictionary = _samples.back()
	if int(tick) <= int(previous.tick):
		if int(tick) == int(previous.tick): _metrics.duplicates += 1
		else: _metrics.stale += 1
		return "ignored"
	var tick_gap := int(tick) - int(previous.tick)
	var elapsed := float(tick_gap) / SERVER_TICK_HZ
	var delta_mm := float(int(position) - int(previous.position_mm))
	var expected_mm := (float(int(previous.velocity_mm_s)) + float(int(velocity))) * 0.5 * elapsed
	var correction_mm := absf(delta_mm - expected_mm)
	var speed_bound := maxf(float(top_speed_mm_s),
		maxf(absf(float(int(previous.velocity_mm_s))), absf(float(int(velocity)))))
	var impossible_step := absf(delta_mm) > speed_bound * elapsed + SNAP_CORRECTION_MM
	var contact_change: bool = contacts != previous.contacts
	if tick_gap > MAX_SAMPLE_GAP_TICKS or correction_mm > SNAP_CORRECTION_MM or impossible_step or contact_change:
		_samples.clear()
		_last_render_tick = float(int(tick)) - INTERPOLATION_DELAY_TICKS
		_append(next)
		_metrics.accepted += 1
		_metrics.snaps += 1
		return "reset"
	_append(next)
	_metrics.accepted += 1
	return "accepted"

func sample_at(now_usec: int) -> Dictionary:
	if _samples.is_empty():
		return {}
	var oldest: Dictionary = _samples.front()
	var newest: Dictionary = _samples.back()
	var age_usec := maxi(0, now_usec - int(newest.received_usec))
	var proposed_tick := float(newest.tick) + float(age_usec) * SERVER_TICK_HZ / 1000000.0 \
		- INTERPOLATION_DELAY_TICKS
	var render_tick := maxf(proposed_tick, _last_render_tick)
	_last_render_tick = render_tick
	if render_tick <= float(oldest.tick):
			return _with_contact_response(_state(oldest, false, false), render_tick)
	for index in range(_samples.size() - 1):
		var left: Dictionary = _samples[index]
		var right: Dictionary = _samples[index + 1]
		if render_tick > float(right.tick):
			continue
		var interval := float(int(right.tick) - int(left.tick))
		var alpha := clampf((render_tick - float(left.tick)) / interval, 0.0, 1.0)
		if left.contacts != right.contacts:
			# Defensive barrier: a contact transition is never blended through.
			return _with_contact_response(_state(left if alpha < 0.5 else right, true, false), render_tick)
		var state := {
			"position_mm": lerpf(float(left.position_mm), float(right.position_mm), alpha),
			"velocity_mm_s": roundi(lerpf(float(left.velocity_mm_s), float(right.velocity_mm_s), alpha)),
			"facing": int(left.facing) if alpha < 1.0 else int(right.facing),
			"simulation_tick": render_tick,
			"contacts": left.contacts.duplicate(),
			"frozen": false,
			"extrapolated": false,
		}
		return _with_contact_response(state, render_tick)
	var requested_ticks := maxf(0.0, render_tick - float(newest.tick))
	var extrapolation_ticks := minf(requested_ticks, MAX_EXTRAPOLATION_TICKS)
	var raw_distance := float(newest.velocity_mm_s) * extrapolation_ticks / SERVER_TICK_HZ
	var contact_barrier: bool = not newest.contacts.is_empty()
	var distance := 0.0 if contact_barrier else clampf(raw_distance, -MAX_EXTRAPOLATION_MM, MAX_EXTRAPOLATION_MM)
	var distance_limited := absf(raw_distance) > MAX_EXTRAPOLATION_MM
	var frozen: bool = contact_barrier or requested_ticks > MAX_EXTRAPOLATION_TICKS or distance_limited
	if extrapolation_ticks > 0.0 and not contact_barrier:
		_metrics.extrapolated += 1
		_metrics.max_extrapolation_ms = maxf(_metrics.max_extrapolation_ms, extrapolation_ticks * 1000.0 / SERVER_TICK_HZ)
		_metrics.max_extrapolation_mm = maxf(_metrics.max_extrapolation_mm, absf(distance))
	if frozen: _metrics.frozen += 1
	var state := {
		"position_mm": float(newest.position_mm) + distance,
		"velocity_mm_s": 0 if frozen else int(newest.velocity_mm_s),
		"facing": int(newest.facing),
		"simulation_tick": float(newest.tick) + extrapolation_ticks,
		"contacts": newest.contacts.duplicate(),
		"frozen": frozen,
		"extrapolated": extrapolation_ticks > 0.0 and not contact_barrier,
	}
	return _with_contact_response(state, render_tick)

func prediction_hint(now_usec: int, lead_ticks: float) -> Dictionary:
	# Separate from delayed rendering: bounded physical hints, never peer intent.
	if _samples.is_empty(): return {}
	var latest: Dictionary = _samples.back()
	if now_usec - int(latest.received_usec) > 200000: return {}
	var ticks := clampf(lead_ticks, 0.0, MAX_EXTRAPOLATION_TICKS)
	var distance := clampf(float(latest.velocity_mm_s) * ticks / SERVER_TICK_HZ,
		-MAX_EXTRAPOLATION_MM, MAX_EXTRAPOLATION_MM)
	return {"position_mm":float(latest.position_mm)+distance,
		"velocity_mm_s":int(latest.velocity_mm_s),"contacts":latest.contacts.duplicate()}

func metrics() -> Dictionary:
	var result := _metrics.duplicate(true)
	result["sample_count"] = _samples.size()
	result["latest_tick"] = latest_tick()
	return result

func _append(sample: Dictionary) -> void:
	if int(sample.contact_response_tick) > _latest_response_tick:
		_latest_response_tick = int(sample.contact_response_tick)
		_responses.append({"contact_response_tick":_latest_response_tick,
			"contact_delta_velocity_mm_s":int(sample.contact_delta_velocity_mm_s),
			"contact_response_facing":int(sample.contact_response_facing),
			"contact_response_contacts":sample.contact_response_contacts.duplicate(),
			"contact_impact_sources":sample.contact_impact_sources.duplicate()})
		while _responses.size() > MAX_SAMPLES: _responses.pop_front()
	_samples.append(sample)
	while _samples.size() > MAX_SAMPLES:
		_samples.pop_front()
	_metrics.sample_peak = maxi(int(_metrics.sample_peak), _samples.size())

func _state(sample: Dictionary, contact_barrier: bool, extrapolated: bool) -> Dictionary:
	return {
		"position_mm": float(sample.position_mm),
		"velocity_mm_s": 0 if contact_barrier else int(sample.velocity_mm_s),
		"facing": int(sample.facing),
		"simulation_tick": int(sample.tick),
		"contacts": sample.contacts.duplicate(),
		"frozen": contact_barrier,
		"extrapolated": extrapolated,
	}

func _with_contact_response(state: Dictionary, render_tick: float) -> Dictionary:
	var response_tick := -1
	var response: Dictionary = {}
	for sample in _responses:
		var candidate_tick := int(sample.contact_response_tick)
		if int(sample.contact_delta_velocity_mm_s) == 0 or float(candidate_tick) > render_tick \
			or candidate_tick <= response_tick:
			continue
		response_tick = candidate_tick
		response = sample
	if response.is_empty():
		state.merge({"contact_delta_velocity_mm_s": 0, "contact_response_facing": 0,
			"contact_response_tick": 0, "contact_response_contacts": [], "contact_impact_sources": []}, true)
	else:
		state.merge({"contact_delta_velocity_mm_s": int(response.contact_delta_velocity_mm_s),
			"contact_response_facing": int(response.contact_response_facing),
			"contact_response_tick": response_tick,
			"contact_response_contacts": response.contact_response_contacts.duplicate(),
			"contact_impact_sources": response.contact_impact_sources.duplicate()}, true)
	return state
