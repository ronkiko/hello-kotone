extends RefCounted
## Reconciles authoritative held-input steps against the nominal path for each accepted input sequence.
const Protocol = preload("res://scripts/mmo/protocol_v4.gd")
var _baseline: Dictionary = {}
var _confirmed_x: Variant = null
var _healthy := false
var _min_x := 0
var _max_x := 0
var _step := 1
var _active_seq := 0
var _records: Dictionary = {}

func observe(document: Dictionary, replica: Dictionary, step_units: int) -> bool:
	if not Protocol.map_definition(document) or not Protocol.map_reference(replica.get("map")):
		clear()
		return false
	for key in ["map_id", "content_version", "content_hash"]:
		if document[key] != replica.map[key]:
			clear()
			return false
	var x: Variant = replica.get("confirmed_local_x")
	if not Protocol.integer(x, document.min_x, document.max_x) or step_units != 1:
		clear()
		return false
	var baseline := {"epoch": replica.get("epoch"), "map": replica.map.duplicate(true),
		"player_id": replica.get("local_player_id")}
	if not Protocol.token(baseline.epoch) or not Protocol.token(baseline.player_id):
		clear()
		return false
	if baseline != _baseline:
		_records = {}
		_active_seq = 0
	_baseline = baseline
	_confirmed_x = x
	_min_x = document.min_x
	_max_x = document.max_x
	_step = step_units
	_healthy = replica.get("status") == "SYNCED" and not replica.get("reconnect_required", true)
	return true

func accept_input(input_seq: int, direction: String, baseline_x: int) -> bool:
	if not _healthy or input_seq < 1 or direction not in ["left", "right", "stop"] \
			or not Protocol.integer(baseline_x, _min_x, _max_x):
		return false
	_active_seq = input_seq
	_records[input_seq] = {"direction": direction, "baseline_x": baseline_x,
		"step_count": 0, "last_error": 0}
	for seq in _records.keys():
		if int(seq) < input_seq - 4:
			_records.erase(seq)
	return true

func authoritative_step(actual_x: int) -> float:
	if not _healthy or _active_seq == 0 or not _records.has(_active_seq) \
			or not Protocol.integer(actual_x, _min_x, _max_x):
		_confirmed_x = actual_x
		return 0.0
	var record: Dictionary = _records[_active_seq]
	if record.direction == "stop":
		_confirmed_x = actual_x
		return 0.0
	record.step_count += 1
	var sign := -1 if record.direction == "left" else 1
	var expected: int = clampi(record.baseline_x + sign * record.step_count * _step, _min_x, _max_x)
	var error := actual_x - expected
	var delta := error - record.last_error
	record.last_error = error
	_records[_active_seq] = record
	_confirmed_x = actual_x
	return float(delta)

func clear() -> void:
	_baseline = {}
	_confirmed_x = null
	_healthy = false
	_active_seq = 0
	_records = {}

func view() -> Dictionary:
	return {"confirmed_x": _confirmed_x, "active_input_seq": _active_seq,
		"healthy": _healthy, "active": _active_seq != 0, "predicted_x": null,
		"target_x": _confirmed_x, "records": _records.duplicate(true)}
