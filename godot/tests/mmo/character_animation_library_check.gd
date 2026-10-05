extends SceneTree
## Character animation package/SpriteFrames boundary checks.
const Library = preload("res://scripts/presentation/character_animation_library.gd")

var checks := 0
var failures := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _initialize() -> void:
	run.call_deferred()

func _frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	for animation in Library.REQUIRED_ANIMATIONS:
		frames.add_animation(animation)
		frames.add_frame(animation, texture)
	return frames

func run() -> void:
	check(Library.valid_model_id("kotone"), "lowercase model id accepted")
	check(Library.valid_model_id("yuna_v1"), "underscore model id accepted")
	check(not Library.valid_model_id("Yuna"), "uppercase model id rejected")
	check(not Library.valid_model_id("../yuna"), "path traversal rejected")
	check(Library.package_root("yuna") == "res://assets/characters/yuna", "canonical package root")
	check(Library.sprite_frames_path("yuna") == "res://assets/characters/yuna/sprite_frames.tres", "canonical SpriteFrames path")

	var frames := _frames()
	check(Library.has_required_animations(frames), "idle and directional walk animations required")

	var incomplete := SpriteFrames.new()
	check(not Library.has_required_animations(incomplete), "incomplete animation resource rejected")

	var sprite := AnimatedSprite2D.new()
	root.add_child(sprite)
	check(Library.configure_sprite(sprite, frames), "canonical SpriteFrames config accepted")
	check(sprite.sprite_frames == frames, "SpriteFrames installed")
	check(not sprite.centered, "canonical visual is not texture-centered")
	check(sprite.position == Vector2(-128, -236), "frame pivot maps to root origin")
	check(sprite.scale == Vector2.ONE, "canonical asset uses unit sprite scale")

	check(Library.load_frames("missing_model") == null, "missing package has no fallback")
	sprite.queue_free()

	print(JSON.stringify({
		"suite": "character-animation-library",
		"checks": checks,
		"failures": failures,
		"result": "PASS" if failures.is_empty() else "FAIL",
	}))
	quit(0 if failures.is_empty() else 1)
