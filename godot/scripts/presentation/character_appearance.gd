extends Node2D
## Local hello-kotone semantic mapping, shared by Creator and world avatars.
const MODELS := {
	"kotone": {"body_variant_id": ["standard"],
		"face_style_id": ["soft", "bright"], "hair_style_id": ["short", "long"],
		"hair_color_id": ["chestnut", "black", "silver"]},
	"yuna": {"body_variant_id": ["standard"],
		"face_style_id": ["soft", "bright"], "hair_style_id": ["bob"],
		"hair_color_id": ["rose", "black", "silver"]},
}
const COLORS := {"chestnut": Color("8c5039"), "black": Color("272534"), "silver": Color("c5d4e2"), "rose": Color("df7b87")}
const Library = preload("res://scripts/presentation/character_animation_library.gd")
# Shared viewport presentation transform; canonical sprite scale remains one.
const DISPLAY_SCALE := 0.48

static func display_height_px(character_model_id: String) -> float:
	return float(Library.FrameContract.canonical_height_px(character_model_id)) * DISPLAY_SCALE

static func model_supported(character_model_id: String) -> bool:
	return MODELS.has(character_model_id) and Library.load_frames(character_model_id) != null

static func catalog_model_supported(character_model_id: String, model: Dictionary) -> bool:
	if not model_supported(character_model_id) or not supported(model.default_payload): return false
	var local: Dictionary = MODELS[character_model_id]
	if model.options.size() != local.size(): return false
	for key in model.options:
		if not local.has(key): return false
		for option in model.options[key]:
			if not option in local[key]: return false
	return true

static func idle_animation(facing: int) -> StringName:
	return &"idle_left" if facing < 0 else &"idle_right"

static func walk_animation(facing: int) -> StringName:
	return &"walk_left" if facing < 0 else &"walk_right"

static func walk_frame_count(sprite: AnimatedSprite2D, facing: int) -> int:
	return sprite.sprite_frames.get_frame_count(walk_animation(facing))

static func pose(sprite: AnimatedSprite2D, walking: bool, facing: int, index: int) -> void:
	if sprite.sprite_frames == null: return
	# Gait owns progression from displacement. Native playback stays paused so a
	# blocked/stale world cannot advance legs independently of rendered movement.
	sprite.pause()
	sprite.animation = walk_animation(facing) if walking else idle_animation(facing)
	sprite.frame = posmod(index, sprite.sprite_frames.get_frame_count(sprite.animation))

static func idle_frame(sprite: AnimatedSprite2D, elapsed: float, facing: int = 1) -> int:
	var frames := sprite.sprite_frames
	var animation := idle_animation(facing)
	var count := frames.get_frame_count(animation)
	var total := 0.0
	for i in range(count): total += frames.get_frame_duration(animation, i)
	var cursor := fmod(maxf(elapsed, 0.0) * frames.get_animation_speed(animation), total)
	for i in range(count):
		cursor -= frames.get_frame_duration(animation, i)
		if cursor < 0.0: return i
	return 0

var payload := {}
var hair_color := Color.WHITE
static func supported(value: Variant) -> bool:
	if not value is Dictionary: return false
	var options: Dictionary = MODELS.get(value.get("character_model_id", ""), {})
	if not model_supported(value.get("character_model_id", "")) or options.is_empty() or value.size() != options.size() + 1: return false
	for key in options:
		if not value.get(key) in options[key]: return false
	return true

static func install(sprite: AnimatedSprite2D, value: Dictionary) -> bool:
	if not supported(value) or Library.load_frames(value.character_model_id) == null: return false
	var overlay: Node2D = sprite.get_node_or_null("SemanticAppearance")
	if overlay == null:
		overlay = load("res://scripts/presentation/character_appearance.gd").new()
		overlay.name = "SemanticAppearance"
		overlay.z_index = -1
		sprite.add_child(overlay)
	if overlay.payload == value: return true
	if not Library.install(sprite, value.character_model_id): return false
	overlay.payload = value.duplicate(true)
	overlay.hair_color = COLORS[value.hair_color_id]
	sprite.set_meta("character_model_id", value.character_model_id)
	pose(sprite, false, 0, 0)
	overlay.queue_redraw()
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
	uniform vec4 hair_color : source_color;
	uniform float bright;
	uniform bool yuna;
	void fragment() {
		vec4 c = texture(TEXTURE, UV);
		float head_y = UV.y;
		// Pink pixels in the head/hair area of the existing art become the preset.
		if (head_y < 0.46 && ((c.r > c.g * 1.18 && c.b > c.g * 1.06) || (yuna && head_y < 0.43 && c.r > c.g * 1.4 && c.r > c.b * 1.2)) && c.a > 0.0) {
			float shade = clamp((c.r + c.g + c.b) / 2.1, 0.25, 1.3);
			c.rgb = hair_color.rgb * shade;
		} else if (head_y < 0.45 && c.r > c.b * 1.1 && c.r > c.g) {
			c.rgb = mix(c.rgb, vec3(1.0, 0.82, 0.73), bright * 0.3);
		}
		COLOR = c;
	}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("hair_color", COLORS[value.hair_color_id])
	material.set_shader_parameter("yuna", value.character_model_id == "yuna")
	material.set_shader_parameter("bright", 1.0 if value.face_style_id == "bright" else 0.0)
	sprite.material = material
	return true

func _draw() -> void:
	if payload.get("hair_style_id") == "long":
		# Cosmetic strands follow the sprite; no collision, scale or physics change.
		draw_colored_polygon(PackedVector2Array([Vector2(118,76), Vector2(111,94), Vector2(110,126), Vector2(121,120), Vector2(124,86)]), hair_color)
		draw_colored_polygon(PackedVector2Array([Vector2(137,76), Vector2(144,94), Vector2(146,126), Vector2(135,120), Vector2(131,86)]), hair_color)
