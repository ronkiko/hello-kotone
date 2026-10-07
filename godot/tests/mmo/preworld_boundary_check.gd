extends SceneTree
## Current v7 authority/failure invariants using adversarial delayed public replies.
const Protocol = preload("res://scripts/mmo/protocol_v8.gd")
var pre: Node
var checks := 0
var failures: Array = []
class DelayedPeer extends Node:
	signal lost(code: String)
	var connected_ok := true
	var pending := {}
	var last_at := 0
	var spacing_ms := 1
	var reply := {}
	var sent: Array = []
	func close() -> void:
		connected_ok = false
		pending = {}
	func request(op: String, payload: Dictionary) -> Dictionary:
		sent.append({"op": op, "payload": payload.duplicate(true)})
		pending = {"op": op}
		await get_tree().process_frame
		pending = {}
		return reply

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func scope() -> void:
	pre.account_id = "account-one"
	pre.realm = {"game_card_id": "hello-kotone", "realm_id": "test", "display_name": "Test"}
	pre._binding = {"lobby_session_id": "a".repeat(64), "lobby_generation": 1}
	pre.state = "LOBBY"
	pre.error = {}

func result(op: String, data: Dictionary) -> Dictionary:
	return {"protocol_version": 8, "type": "response", "request_id": "r1", "op": op, "status": "ok", "data": data, "error": null}

func record() -> Dictionary:
	return {"game_card_id": "hello-kotone", "realm_id": "test", "account_id": "account-one", "character_id": "char-one", "display_name": "Alice Kotone", "slot": 1, "lifecycle_state": "active", "character_schema_version": 1, "appearance_schema_version": 2,
		"appearance_payload": {"character_model_id": "kotone", "body_variant_id": "standard", "face_style_id": "soft", "hair_style_id": "short", "hair_color_id": "silver"}, "initial_spawn_profile": "default", "created_at_ms": 1, "updated_at_ms": 1}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	pre = root.get_node("Preworld")
	pre.set_process(false)
	var real_peer: Node = pre._lobby
	var peer := DelayedPeer.new()
	root.add_child(peer)
	pre._lobby = peer
	scope()
	check(Protocol.character_record(record()), "current Registry fixture")
	check(Protocol.response(result("character_select", {"character": record(), "character_generation": 1})), "current selection wire")
	var old := result("character_select", {"character": record(), "character_generation": 1})
	old.protocol_version = 6
	check(not Protocol.response(old), "v6 rejected")
	for status in ["full", "closed", "unavailable"]:
		pre.state = "REALMS"
		pre.realms = [{"game_card_id": "hello-kotone", "realm_id": "test", "status": status}]
		pre.select_realm(0)
		check(pre.state == "REALMS" and peer.sent.is_empty(), "unavailable realm cannot dispatch " + status)
	scope()
	peer.reply = result("character_select", {"character": record(), "character_generation": 1})
	pre.select_character("char-one")
	pre.back_to_realms() # Selection pending cannot Back; explicit account logout cancels.
	pre.logout_account()
	await process_frame
	await process_frame
	check(pre.state == "LOGIN" and pre.selection.is_empty() and pre._binding.is_empty(), "late select cannot restore account authority")
	for key in ["account_id", "realm_id", "character_id"]:
		scope()
		peer.connected_ok = true
		var foreign := record()
		foreign[key] = "foreign"
		peer.reply = result("character_select", {"character": foreign, "character_generation": 1})
		await pre.select_character("char-one")
		check(pre.state == "FAILED" and pre.selection.is_empty(), "foreign selection fenced " + key)
	scope()
	peer.connected_ok = true
	pre.selection = {"character": record(), "character_generation": 1}
	peer.reply = {"status": "rejected", "error": {"code": "DURABILITY_UNSAFE"}}
	await pre.select_character("char-one")
	check(pre.state == "LOBBY" and pre.selection.is_empty() and pre.error.code == "DURABILITY_UNSAFE", "unsafe Registry barrier never gives World selection")
	scope()
	peer.connected_ok = true
	var unknown := record()
	unknown.appearance_payload.character_model_id = "uninstalled"
	peer.reply = result("character_select", {"character": unknown, "character_generation": 1})
	await pre.select_character("char-one")
	check(pre.state == "FAILED" and pre.selection.is_empty() and pre.error.code == "APPEARANCE_INCOMPATIBLE", "server-valid unknown local presenter has no admission fallback")
	scope()
	pre.catalog = {"appearance_schema_version": 2}
	pre.state = "CREATOR"
	peer.reply = {}
	await pre.create_character("Alice Kotone", record().appearance_payload)
	var remembered: Dictionary = pre._mutation.duplicate(true)
	check(pre.state == "FAILED" and pre.error.outcome_unknown and remembered.payload.idempotency_key.length() == 32, "lost create remains unknown with separate key")
	check(peer.sent[-1].payload.idempotency_key == remembered.payload.idempotency_key and not pre.error.has("idempotency_key"), "wire key retained without UI leak")
	pre.logout_account()
	scope()
	peer.connected_ok = true
	check(pre.mutation_pending and pre._mutation == remembered, "fresh visit retains unresolved mutation")
	pre.realm.realm_id = "general"
	check(not pre.mutation_pending, "unknown receipt cannot cross realm")
	pre.realm.realm_id = "test"
	pre.account_id = "account-other"
	check(not pre.mutation_pending, "unknown receipt cannot cross account")
	pre.account_id = "account-one"
	peer.reply = result("character_create", {"character": record(), "character_generation": 1})
	# A successful historical receipt is reconciled by a fresh list, not selection.
	pre.reconcile_mutation()
	await process_frame
	await process_frame
	check(peer.sent[-1].payload.get("idempotency_key", remembered.payload.idempotency_key) == remembered.payload.idempotency_key, "explicit retry uses identical key")
	pre._receipts.clear()
	for index in range(8):
		pre._receipts["old-account-%d/hello-kotone/old-realm" % index] = remembered.duplicate(true)
	scope()
	pre.state = "CREATOR"
	pre.catalog = {"appearance_schema_version": 2}
	peer.connected_ok = true
	peer.reply = {}
	var sent_before := peer.sent.size()
	await pre.create_character("New Alice", record().appearance_payload)
	check(peer.sent.size() == sent_before + 1 and peer.sent[-1].op == "character_create" and pre.mutation_pending, "unresolved receipts in other scopes do not block create")
	check(pre._receipts.size() == 9, "new ambiguous mutation preserves older receipts")
	pre.logout_account()
	scope()
	peer.connected_ok = true
	pre.selection = {"character": record(), "character_generation": 1}
	pre.availability = {"status": "online"}
	peer.reply = result("world_enter", {"world_handoff": "f".repeat(64), "expires_in_ms": 30000, "character_id": "char-foreign", "identity": {"game_card_id": "hello-kotone", "realm_id": "test", "realm_instance_id": "boot-one"}, "game": {"host": "127.0.0.1", "port": 1}})
	await pre.enter_world()
	check(pre.state == "FAILED" and pre.selection.is_empty() and root.get_node("MmoClient").session_id.is_empty(), "wrong character handoff cannot open Game authority")
	scope()
	pre.state = "WORLD"
	pre._game_fault({"code": "REQUEST_TIMEOUT", "outcome_unknown": true})
	check(pre.state == "FAILED" and pre.error.phase == "Game" and pre.error.outcome_unknown, "Game unknown outcome distinct from Lobby")
	scope()
	pre.state = "LOBBY_WORKING"
	var visit: int = pre._visit
	pre._lobby_lost("DISCONNECTED")
	check(pre.error.phase == "Lobby" and pre._binding.is_empty() and pre._visit > visit, "Lobby loss revokes visit and fences callbacks")
	pre._lobby = real_peer
	peer.queue_free()
	pre.logout_account()
	print(JSON.stringify({"suite": "preworld-boundaries", "checks": checks, "failures": failures, "result": "PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
