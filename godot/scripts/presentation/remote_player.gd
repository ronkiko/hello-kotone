extends Node2D
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
var player_id := ""
var sprite := AnimatedSprite2D.new()
var visual_layer := Node2D.new()
var identity := Label.new()
var visual_x: float:
	get: return position.x
var target_x: float:
	get: return position.x
var suspended := false

func _ready() -> void:
	visual_layer.scale = Vector2.ONE * Appearance.DISPLAY_SCALE
	add_child(visual_layer)
	visual_layer.add_child(sprite)
	identity.position.x = -64
	identity.size = Vector2(128, 18)
	identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity.add_theme_font_size_override("font_size", 11)
	add_child(identity)

func project(player: Dictionary, confirmed_pixel: float) -> void:
	position.x = confirmed_pixel
	identity.text = player.nickname
	Appearance.install(sprite, player.character.appearance_payload)
	identity.position.y = -Appearance.display_height_px(player.character.appearance_payload.character_model_id) - 18
	var motion: Dictionary = player.motion
	var animation := ("walk_" if motion.velocity_mm_s != 0 else "idle_") + ("left" if motion.facing < 0 else "right")
	if suspended: sprite.pause()
	else: sprite.play(animation)
