extends SceneTree
## Hostile catalog, client content incompatibility and card-local presentation.
const Protocol = preload("res://scripts/mmo/protocol_v7.gd")
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const Gait = preload("res://scripts/presentation/gait_animator.gd")
var checks := 0
var failures := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var kotone := {"character_model_id": "kotone", "body_variant_id": "standard", "face_style_id": "soft", "hair_style_id": "short", "hair_color_id": "chestnut"}
	var yuna := {"character_model_id": "yuna", "body_variant_id": "standard", "face_style_id": "bright", "hair_style_id": "bob", "hair_color_id": "rose"}
	check(Appearance.supported(kotone) and Appearance.supported(yuna), "two installed presenters")
	for change in [{"character_model_id": "unknown"}, {"hair_style_id": "long"}, {"hair_color_id": "chestnut"}, {"scene": "res://fake.tscn"}, {"archetype_id": "resident"}]:
		var bad := yuna.duplicate(true)
		bad.merge(change, true)
		check(not Appearance.supported(bad), "unknown/cross-model/path rejected")
	for value in [kotone, yuna]:
		var options: Dictionary = Appearance.MODELS[value.character_model_id]
		check(Appearance.catalog_model_supported(value.character_model_id, {"options": options,"default_payload":value}), "canonical catalog accepted without removed archetype field")
	var sprite := AnimatedSprite2D.new()
	root.add_child(sprite)
	check(Appearance.install(sprite, yuna), "Yuna installed")
	check(sprite.animation == &"idle" and sprite.sprite_frames.get_frame_count(&"idle") == 16, "canonical Yuna idle frames")
	var gait := Gait.new()
	gait.configure(10)
	gait.update(sprite, 0, -3, -5, -1, 0.1)
	check(sprite.animation == &"walk_left" and not sprite.flip_h and sprite.sprite_frames.get_frame_count(&"walk_left") == 8, "Yuna left walk uses offline mirrored frames")
	gait.update(sprite, -3, -3, -3, 0, 0.1)
	check(sprite.animation == &"idle" and not sprite.flip_h, "Yuna release returns idle")
	check(Appearance.install(sprite, kotone), "Kotone installed")
	check(sprite.animation == &"idle" and sprite.sprite_frames.get_frame_count(&"idle") == 6, "model switch installs native package")
	var options := {"signal_id": ["steady", "pulse"]}
	var catalog := {"game_card_id": "independent", "catalog_version": 2, "appearance_schema_version": 2,
		"character_models": {"beacon": {"options": options, "default_payload": {"character_model_id": "beacon", "signal_id": "steady"}}},
		"default_character_model_id": "beacon", "initial_spawn_profiles": ["default"], "default_spawn_profile": "default"}
	check(Protocol.catalog(catalog), "generic independent model catalog")
	check(not Appearance.model_supported("beacon"), "server-valid model without local content has no fallback")
	for change in [{"character_models": {}}, {"default_character_model_id": "unknown"}, {"catalog_version": 1}, {"appearance_schema_version": 1}, {"options": options}, {"legacy_empty_policy": "default"}]:
		var bad := catalog.duplicate(true)
		bad.merge(change, true)
		check(not Protocol.catalog(bad), "obsolete/unbounded catalog rejected")
	var bad := catalog.duplicate(true)
	bad.character_models.beacon.default_payload.character_model_id = "foreign"
	check(not Protocol.catalog(bad), "default model identity cannot disagree")
	bad = catalog.duplicate(true)
	bad.character_models.beacon.options.signal_id = ["steady", "steady"]
	check(not Protocol.catalog(bad), "duplicate model options rejected")
	sprite.queue_free()
	print(JSON.stringify({"suite": "character-models", "checks": checks, "failures": failures, "result": "PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
