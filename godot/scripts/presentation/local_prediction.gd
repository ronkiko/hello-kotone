extends RefCounted
## One speculative display step. Owns neither authoritative facts nor requests.
const Protocol = preload("res://scripts/mmo/protocol_v4.gd")
var _baseline: Dictionary = {}
var _confirmed_x: Variant = null
var _predicted_x: Variant = null
var _healthy := false
var _active := false
var _min_x := 0
var _max_x := 0
var _step := 1

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
	if baseline != _baseline or x != _confirmed_x:
		reconcile()
	_baseline = baseline
	_confirmed_x = x
	_min_x = document.min_x
	_max_x = document.max_x
	_step = step_units
	_healthy = replica.get("status") == "SYNCED" and not replica.get("reconnect_required", true)
	if not _healthy:
		reconcile()
	return true

func begin(direction: String) -> bool:
	if not _healthy or _active or direction not in ["left", "right"]:
		return false
	_predicted_x = clampi(_confirmed_x + (-_step if direction == "left" else _step), _min_x, _max_x)
	_active = true
	return true

func reconcile() -> void:
	_active = false
	_predicted_x = null

func clear() -> void:
	reconcile()
	_baseline = {}
	_confirmed_x = null
	_healthy = false

func view() -> Dictionary:
	return {"confirmed_x": _confirmed_x, "predicted_x": _predicted_x,
		"target_x": _predicted_x if _active else _confirmed_x,
		"active": _active, "healthy": _healthy}
