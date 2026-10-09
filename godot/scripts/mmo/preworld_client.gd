extends Node
## Account/realm/lifecycle authority. No spatial fields or gameplay simulation.
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const Protocol = preload("res://scripts/mmo/protocol_v8.gd")
const Peer = preload("res://scripts/mmo/public_peer.gd")
signal changed
var state := "LOGIN"
var error := {}
var account_id := ""
var realms: Array = []
var realm := {}
var roster := {}
var catalog := {}
var selection := {}
var availability := {}
var login_endpoint := {"host": "127.0.0.1", "port": 24000}
var profile := "trusted_local_dev"
var username := "dev1"
var trusted_ca: X509Certificate
var _binding := {}
var _rules := {}
var _visit := 0
var _login: Node
var _lobby: Node
var _signout_after_world := false
var _receipts := {}
var _mutation: Dictionary:
	get: return _receipts.get(_receipt_scope(), {})
	set(value):
		if value.is_empty(): _receipts.erase(_receipt_scope())
		else: _receipts[_receipt_scope()] = value

func _receipt_scope() -> String:
	return account_id + "/" + str(realm.get("game_card_id", "")) + "/" + str(realm.get("realm_id", ""))

var mutation_pending: bool:
	get: return not _mutation.is_empty()

func _ready() -> void:
	_login = Peer.new()
	_lobby = Peer.new()
	add_child(_login)
	add_child(_lobby)
	_lobby.lost.connect(_lobby_lost)
	MmoClient.fault.connect(_game_fault)
	MmoClient.response_received.connect(_game_reply)

func _state(value: String) -> void:
	state = value
	changed.emit()

func login(host: String, port: int, user: String, password: String, security_profile: String, ca: X509Certificate = null) -> void:
	if state not in ["LOGIN", "FAILED", "REALMS"]: return
	logout_account()
	profile = security_profile
	trusted_ca = ca
	login_endpoint = {"host": host, "port": port}
	username = user
	if not Protocol.endpoint(login_endpoint) or not Protocol.token(user) or profile not in ["trusted_local_dev", "internet_beta"]:
		_failure("Login", "INVALID_CONFIG")
		return
	var visit := _visit
	_state("LOGIN_CONNECTING")
	if not await _login.open(login_endpoint, profile, trusted_ca):
		if visit == _visit: _failure("Login", _login.last_failure)
		return
	if visit != _visit: return
	_state("AUTHORIZING")
	var credentials := {"dev_account": user} if profile == "trusted_local_dev" else {"username": user, "password": password}
	password = ""
	var reply: Dictionary = await _login.request("login", credentials)
	credentials.clear()
	if visit != _visit: return
	if not _accept(reply, "Login"): return
	account_id = reply.data.account_id
	realms = reply.data.realms.duplicate(true)
	error = {}
	_state("REALMS")

func select_realm(index: int) -> void:
	if state != "REALMS" or index < 0 or index >= realms.size(): return
	var target: Dictionary = realms[index]
	if target.status != "online" or target.game_card_id != "hello-kotone": return
	if not _login.connected_ok:
		error = {"phase": "Login", "code": "REAUTH_REQUIRED", "outcome_unknown": false}
		_state("LOGIN")
		return
	var visit := _visit
	_state("REALM_HANDOFF")
	var reply: Dictionary = await _login.request("select_realm", {"game_card_id": target.game_card_id, "realm_id": target.realm_id})
	if visit != _visit or not _accept(reply, "Login"): return
	if reply.data.realm != target:
		_failure("Login", "REALM_IDENTITY_MISMATCH")
		return
	realm = target.duplicate(true)
	var handoff: String = reply.data.realm_handoff
	reply.clear()
	_state("LOBBY_CONNECTING")
	if not await _lobby.open(realm.lobby, profile, trusted_ca):
		if visit == _visit: _failure("Lobby", "CONNECT_FAILED")
		return
	if visit != _visit: return
	_state("LOBBY_ENTERING")
	reply = await _lobby.request("lobby_enter", {"realm_handoff": handoff})
	handoff = ""
	_login.close()
	if visit != _visit or not _accept(reply, "Lobby"): return
	var session: Dictionary = reply.data.lobby_session
	if session.account_id != account_id or not _scope(session):
		_failure("Lobby", "REALM_IDENTITY_MISMATCH")
		return
	_binding = {"lobby_session_id": session.lobby_session_id, "lobby_generation": session.lobby_generation}
	_install_rules(reply.data)
	await refresh_roster()

func _scope(value: Dictionary) -> bool:
	return value.get("game_card_id") == realm.get("game_card_id") and value.get("realm_id") == realm.get("realm_id")

func _install_rules(data: Dictionary) -> void:
	_rules = data.session_rules.duplicate(true)
	_lobby.spacing_ms = _rules.min_request_interval_ms + 1
	availability = data.world_availability.duplicate(true)

func refresh_roster() -> void:
	if _binding.is_empty() or not _lobby.connected_ok: return
	var visit := _visit
	selection = {}
	_state("LOBBY_LOADING")
	while not _lobby.pending.is_empty():
		await get_tree().process_frame
		if visit != _visit or not _lobby.connected_ok: return
	var reply: Dictionary = await _lobby.request("character_list", _binding.duplicate())
	if visit != _visit or not _accept(reply, "Lobby"): return
	if not _scope(reply.data) or reply.data.account_id != account_id:
		_failure("Lobby", "REALM_IDENTITY_MISMATCH")
		return
	roster = reply.data.duplicate(true)
	reply = await _lobby.request("character_catalog", _binding.duplicate())
	if visit != _visit or not _accept(reply, "Lobby"): return
	if not _scope(reply.data):
		_failure("Lobby", "REALM_IDENTITY_MISMATCH")
		return
	catalog = reply.data.catalog.duplicate(true)
	error = {}
	_state("LOBBY")

func select_character(id: String) -> void:
	if state != "LOBBY" or not Protocol.token(id): return
	selection = {}
	var reply := await _operation("character_select", {"character_id": id})
	if reply.is_empty(): return
	if not _owned(reply.data.character) or reply.data.character.character_id != id:
		_failure("Lobby", "CHARACTER_MISMATCH")
		return
	if not Appearance.supported(reply.data.character.appearance_payload):
		_failure("Lobby", "APPEARANCE_INCOMPATIBLE")
		return
	selection = reply.data.duplicate(true)
	_state("LOBBY")

func _owned(record: Dictionary) -> bool:
	return _scope(record) and record.account_id == account_id

func show_creator() -> void:
	if state == "LOBBY" and not catalog.is_empty() and roster.characters.size() < roster.slot_limit:
		selection = {}
		_state("CREATOR")

func create_character(display: String, payload: Dictionary) -> void:
	if state != "CREATOR" or mutation_pending: return
	# An unknown mutation fences this account/realm only. Receipts in other
	# scopes are retained for explicit reconciliation and must not block this one.
	_mutation = {"op": "character_create", "scope": {"account_id": account_id, "game_card_id": realm.game_card_id, "realm_id": realm.realm_id},
		"payload": {"idempotency_key": Crypto.new().generate_random_bytes(16).hex_encode(), "display_name": display,
		"appearance_schema_version": catalog.appearance_schema_version, "appearance_payload": payload.duplicate(true)}}
	await _run_mutation()

func delete_selected() -> void:
	if state != "LOBBY" or selection.is_empty() or mutation_pending: return
	_mutation = {"op": "character_delete", "scope": {"account_id": account_id, "game_card_id": realm.game_card_id, "realm_id": realm.realm_id},
		"payload": {"idempotency_key": Crypto.new().generate_random_bytes(16).hex_encode(), "character_id": selection.character.character_id,
		"character_generation": selection.character_generation}}
	await _run_mutation()

func reconcile_mutation() -> void:
	# Explicit action only, same durable key and payload, fresh wire correlation.
	if state != "LOBBY" or not mutation_pending: return
	if _mutation.scope != {"account_id": account_id, "game_card_id": realm.game_card_id, "realm_id": realm.realm_id}: return
	await _run_mutation()

func _run_mutation() -> void:
	var op: String = _mutation.op
	var sent: Dictionary = _mutation.payload.duplicate(true)
	var reply := await _operation(op, sent)
	if reply.is_empty(): return
	if op == "character_create":
		if not _owned(reply.data.character) or reply.data.character.appearance_payload != sent.appearance_payload:
			_failure("Lobby", "CHARACTER_MISMATCH", true)
			return
	else:
		if not _scope(reply.data) or reply.data.character_id != sent.character_id or reply.data.character_generation != sent.character_generation + 1:
			_failure("Lobby", "CHARACTER_MISMATCH", true)
			return
	_mutation = {}
	await refresh_roster()

func enter_world() -> void:
	if state != "LOBBY" or selection.is_empty() or availability.get("status") != "online": return
	var selected: Dictionary = selection.character.duplicate(true)
	selection = {}
	var reply := await _operation("world_enter", {})
	if reply.is_empty(): return
	if not _scope(reply.data.identity) or reply.data.character_id != selected.character_id:
		_failure("Lobby", "CHARACTER_MISMATCH", true)
		return
	_state("WORLD")
	MmoClient.enter_character(reply.data, selected, profile, trusted_ca)
	reply.clear()

func back_to_realms() -> void:
	if state not in ["LOBBY", "CREATOR", "FAILED"]: return
	_visit += 1
	_lobby.close()
	_binding = {}
	_rules = {}
	realm = {}
	roster = {}
	catalog = {}
	selection = {}
	availability = {}
	error = {}
	_state("REALMS" if not realms.is_empty() else "LOGIN")

func logout_account() -> void:
	_visit += 1
	if _login != null: _login.close()
	if _lobby != null: _lobby.close()
	MmoClient.disconnect_world()
	_binding = {}
	_rules = {}
	account_id = ""
	realms = []
	realm = {}
	roster = {}
	catalog = {}
	selection = {}
	availability = {}
	error = {}
	# Retain only an unresolved receipt in RAM, bound to its original account/realm.
	_state("LOGIN")

func _operation(op: String, extra: Dictionary) -> Dictionary:
	if not _lobby.connected_ok: return {}
	var visit := _visit
	var payload := _binding.duplicate()
	payload.merge(extra)
	_state("LOBBY_WORKING")
	while not _lobby.pending.is_empty():
		await get_tree().process_frame
		if visit != _visit or not _lobby.connected_ok: return {}
	var reply: Dictionary = await _lobby.request(op, payload)
	if visit != _visit: return {}
	if not _accept(reply, "Lobby", op in ["character_create", "character_delete"]): return {}
	error = {}
	return reply

func _accept(reply: Dictionary, phase: String, mutation: bool = false) -> bool:
	if reply.is_empty():
		_failure(phase, "DISCONNECTED", mutation)
		return false
	if reply.status != "ok":
		var code: String = reply.error.code
		if reply.status == "rejected":
			var rejected_create: bool = mutation and _mutation.get("op") == "character_create"
			if mutation: _mutation = {}
			error = {"phase": phase, "code": code, "outcome_unknown": false}
			_state("REALMS" if phase == "Login" and not account_id.is_empty() else "LOGIN" if phase == "Login" else "CREATOR" if rejected_create else "LOBBY")
		else:
			_failure(phase, code, mutation or code == "OUTCOME_UNKNOWN")
		return false
	return true

func _failure(phase: String, code: String, unknown: bool = false) -> void:
	selection = {}
	error = {"phase": phase, "code": code, "outcome_unknown": unknown}
	_state("FAILED")

func _lobby_lost(code: String) -> void:
	if _binding.is_empty() and state not in ["LOBBY_ENTERING", "LOBBY_CONNECTING", "LOBBY_LOADING", "LOBBY_WORKING"]: return
	var unknown: bool = state == "LOBBY_WORKING" and mutation_pending
	_visit += 1
	_binding = {}
	_rules = {}
	if state == "WORLD":
		MmoClient.disconnect_world()
		unknown = unknown or MmoClient.last_error.get("outcome_unknown", false)
	_failure("Lobby", code, unknown)

func _game_fault(info: Dictionary) -> void:
	if state != "WORLD":
		return
	var unknown := bool(info.get("outcome_unknown", false))
	var code := str(info.get("code", "DISCONNECTED"))
	# A clean transport loss (the usual local-stand restart case) cannot reuse the
	# old Game/Lobby authority. Drop it immediately and present a fresh sign-in
	# instead of leaving a dead World visit on the generic failure page.
	if not unknown and code in ["DISCONNECTED", "CONNECT_FAILED", "CONNECT_TIMEOUT",
			"FRAME_TIMEOUT", "READ_FAILED", "WRITE_FAILED", "WRITE_TIMEOUT", "REQUEST_TIMEOUT"]:
		logout_account()
		error = {"phase": "Game", "code": "REAUTH_REQUIRED", "outcome_unknown": false}
		changed.emit()
		return
	_failure("Game", code, unknown)

func _game_reply(op: String, data: Dictionary) -> void:
	if op == "logout" and state == "WORLD":
		if data.flush.status == "completed":
			if _signout_after_world:
				_signout_after_world = false
				logout_account()
			else: await refresh_roster()
		else: _failure("Game", "DURABILITY_UNSAFE")

func return_to_lobby() -> void:
	if state == "FAILED" and error.get("phase") == "Game" and _lobby.connected_ok:
		await refresh_roster()

func _process(_delta: float) -> void:
	if _lobby == null or _rules.is_empty() or not _lobby.connected_ok or not _lobby.pending.is_empty(): return
	if state not in ["LOBBY", "CREATOR", "WORLD", "FAILED"]: return
	if Time.get_ticks_msec() - _lobby.last_at < _rules.keepalive_interval_ms: return
	var visit := _visit
	var reply: Dictionary = await _lobby.request("lobby_state", _binding.duplicate())
	if visit != _visit or not _accept(reply, "Lobby"): return
	var session: Dictionary = reply.data.lobby_session
	if session.lobby_session_id != _binding.lobby_session_id or session.lobby_generation != _binding.lobby_generation or session.account_id != account_id or not _scope(session):
		_lobby.close()
		_failure("Lobby", "LOBBY_BINDING_MISMATCH")
		return
	_install_rules(reply.data)
	changed.emit()

func signout() -> void:
	if state == "WORLD":
		_signout_after_world = true
		if not MmoClient.logout(): _signout_after_world = false
	else: logout_account()
