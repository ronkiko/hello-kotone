extends RefCounted
## Canonical local character animation package resolver.
##
## Server/gameplay semantics provide only character_model_id. This class resolves
## that semantic id to a local Godot SpriteFrames resource. It does not inspect
## bitmap bounds and never falls back to another character model.

const FrameContract = preload("res://scripts/presentation/character_sprite_frame_contract.gd")
const PACKAGE_ROOT := "res://assets/characters"
const RESOURCE_NAME := "sprite_frames.tres"
const REQUIRED_ANIMATIONS := [&"idle_left", &"idle_right", &"walk_left", &"walk_right"]

static func valid_model_id(character_model_id: String) -> bool:
	if character_model_id.is_empty() or character_model_id.length() > 64:
		return false
	if character_model_id != character_model_id.to_lower():
		return false
	var regex := RegEx.new()
	if regex.compile("^[a-z0-9][a-z0-9_-]*$") != OK:
		return false
	return regex.search(character_model_id) != null

static func package_root(character_model_id: String) -> String:
	if not valid_model_id(character_model_id):
		return ""
	return "%s/%s" % [PACKAGE_ROOT, character_model_id]

static func sprite_frames_path(character_model_id: String) -> String:
	var root := package_root(character_model_id)
	if root.is_empty():
		return ""
	return "%s/%s" % [root, RESOURCE_NAME]

static func has_required_animations(frames: SpriteFrames) -> bool:
	if frames == null:
		return false
	for animation in REQUIRED_ANIMATIONS:
		if not frames.has_animation(animation):
			return false
		if frames.get_frame_count(animation) <= 0 or frames.get_animation_speed(animation) <= 0:
			return false
		for index in range(frames.get_frame_count(animation)):
			var texture := frames.get_frame_texture(animation, index)
			if texture == null or texture.get_size() != Vector2(FrameContract.frame_size()): return false
	return true

static func load_frames(character_model_id: String) -> SpriteFrames:
	var path := sprite_frames_path(character_model_id)
	if path.is_empty() or not ResourceLoader.exists(path, "SpriteFrames"):
		return null
	var resource := ResourceLoader.load(path, "SpriteFrames")
	var frames := resource as SpriteFrames
	if not has_required_animations(frames):
		return null
	for animation in frames.get_animation_names():
		for index in range(frames.get_frame_count(animation)):
			var texture := frames.get_frame_texture(animation, index)
			if texture == null or not texture.resource_path.begins_with(package_root(character_model_id) + "/" + String(animation) + "/"):
				return null
	return frames

static func configure_sprite(sprite: AnimatedSprite2D, frames: SpriteFrames) -> bool:
	if sprite == null or not has_required_animations(frames):
		return false
	sprite.pause()
	sprite.sprite_frames = frames
	sprite.animation = &"idle_right"
	sprite.frame = 0
	sprite.centered = false
	sprite.position = Vector2(FrameContract.visual_origin_offset())
	sprite.scale = Vector2.ONE
	sprite.flip_h = false
	return true

static func install(sprite: AnimatedSprite2D, character_model_id: String) -> bool:
	var frames := load_frames(character_model_id)
	if not configure_sprite(sprite, frames):
		return false
	sprite.set_meta("character_model_id", character_model_id)
	return true
