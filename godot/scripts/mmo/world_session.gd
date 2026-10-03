extends RefCounted
## Realm binding independent of the currently observed zone. Values only.

const Protocol = preload("res://scripts/mmo/protocol_v6.gd")
var _bootstrap: Dictionary = {}
var _active := false

func view() -> Dictionary:
	return {"active": _active, "identity": _bootstrap.get("identity", {}).duplicate(true),
		"capabilities": _bootstrap.get("capabilities", []).duplicate()}

func bind(value: Dictionary) -> bool:
	# A failed binding can only be replaced by teardown and a fresh Host enter.
	if not _bootstrap.is_empty() or not Protocol.bootstrap(value):
		return false
	_bootstrap = value.duplicate(true)
	_active = true
	return true

func accepts_identity(value: Dictionary) -> bool:
	return _active and Protocol.identity(value) and value == _bootstrap.identity

func accepts_epoch(value: Variant) -> bool:
	return _active and Protocol.token(value) and value == _bootstrap.identity.realm_instance_id

func supports(operation: String) -> bool:
	return _active and operation in _bootstrap.capabilities

func invalidate() -> void:
	_active = false

func clear() -> void:
	_bootstrap = {}
	_active = false
