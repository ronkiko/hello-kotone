extends SceneTree

const Appearance = preload("res://scripts/presentation/character_appearance.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	var pre: Node = root.get_node("Preworld")
	pre.account_id = "account-1"
	pre.realm = {"game_card_id":"hello-kotone","realm_id":"local"}
	pre.availability = {"status":"online"}
	pre.state = "LOBBY"
	pre.roster = {"characters":[{"character_id":"character-1","account_id":"account-1",
		"game_card_id":"hello-kotone","realm_id":"local","appearance_payload":{
			"character_model_id":"kotone","body_variant_id":"standard","face_style_id":"soft",
			"hair_style_id":"short","hair_color_id":"chestnut"}}]}
	var offers: Array[Dictionary] = []
	pre.takeover_offered.connect(func(character: Dictionary): offers.append(character))
	pre.error = {"code":"CHARACTER_ONLINE"}
	check(pre._maybe_offer_takeover("character-1") and offers.size() == 1
		and offers[0].character_id == "character-1" and pre.error.is_empty(),
		"only owned supported CHARACTER_ONLINE offers explicit takeover")
	for code in ["CHARACTER_BUSY", "DURABILITY_UNSAFE"]:
		pre.error = {"code":code}
		check(not pre._maybe_offer_takeover("character-1") and offers.size() == 1,
			code + " never offers takeover")
	pre.error = {"code":"CHARACTER_ONLINE"}
	pre.availability = {"status":"unavailable"}
	check(not pre._maybe_offer_takeover("character-1") and offers.size() == 1,
		"unavailable Realm never offers takeover")
	pre.availability = {"status":"online"}
	pre.roster.characters[0].account_id = "other-account"
	check(not pre._maybe_offer_takeover("character-1") and offers.size() == 1,
		"foreign roster character never offers takeover")
	pre.roster.characters[0].account_id = "account-1"
	pre.roster.characters[0].appearance_payload = {}
	check(not pre._maybe_offer_takeover("character-1") and offers.size() == 1,
		"unsupported appearance never offers takeover")
	check(root.get_node("MmoClient").state == "IDLE",
		"offering takeover does not create a Game connection")
	print(JSON.stringify({"suite":"preworld-takeover-boundary","checks":checks,
		"failures":failures,"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
