extends Node2D
## Local hello-kotone semantic mapping, shared by Creator and world avatars.
const MODELS := {
	"kotone": {"archetype_id": ["resident"], "body_variant_id": ["standard"],
		"face_style_id": ["soft", "bright"], "hair_style_id": ["short", "long"],
		"hair_color_id": ["chestnut", "black", "silver"]},
	"yuna": {"archetype_id": ["resident"], "body_variant_id": ["standard"],
		"face_style_id": ["soft", "bright"], "hair_style_id": ["bob"],
		"hair_color_id": ["rose", "black", "silver"]},
}
const COLORS := {"chestnut": Color("8c5039"), "black": Color("272534"), "silver": Color("c5d4e2"), "rose": Color("df7b87")}
const KOTONE_IDLE = preload("res://assets/kotone_v2_idle_front.png")
const KOTONE_LEFT = preload("res://assets/kotone_v2_walking_left.png")
const KOTONE_RIGHT = preload("res://assets/kotone_v2_walking_right.png")
const YUNA_IDLE = preload("res://assets/yuna_v1_idle_sheet.png")
const YUNA_WALK = preload("res://assets/yuna_v1_walking_right.png")

static func model_supported(character_model_id: String) -> bool:
	return MODELS.has(character_model_id)

static func catalog_model_supported(character_model_id: String, model: Dictionary) -> bool:
	if not model_supported(character_model_id) or not supported(model.default_payload): return false
	var local: Dictionary = MODELS[character_model_id]
	if model.options.size() != local.size(): return false
	for key in model.options:
		if not local.has(key): return false
		for option in model.options[key]:
			if not option in local[key]: return false
	return true

static func walk_frame_count(sprite: Sprite2D) -> int:
	return 8 if sprite.get_meta("character_model_id", "kotone") == "yuna" else 6

static func pose(sprite: Sprite2D, walking: bool, facing: int, index: int) -> void:
	var character_model_id: String = sprite.get_meta("character_model_id", "kotone")
	if not model_supported(character_model_id): return
	var factor: float = sprite.get_meta("presentation_scale", 0.65)
	sprite.region_enabled = false
	sprite.flip_h = false
	sprite.vframes = 1
	if character_model_id == "yuna":
		sprite.texture = YUNA_WALK if walking else YUNA_IDLE
		sprite.hframes = 8
		sprite.vframes = 1 if walking else 2
		sprite.scale = Vector2.ONE * factor * (130.0 / (256.0 if walking else 397.0))
		sprite.flip_h = walking and facing < 0
	else:
		sprite.texture = KOTONE_LEFT if walking and facing < 0 else KOTONE_RIGHT if walking else KOTONE_IDLE
		sprite.hframes = 6
		sprite.scale = Vector2.ONE * factor
	sprite.frame = posmod(index, sprite.hframes * sprite.vframes)
	if sprite.material is ShaderMaterial:
		sprite.material.set_shader_parameter("sheet_rows", float(sprite.vframes))
		sprite.material.set_shader_parameter("walking_yuna", character_model_id == "yuna" and walking)

var payload := {}
var hair_color := Color.WHITE
static func supported(value: Variant) -> bool:
	if not value is Dictionary: return false
	var options: Dictionary = MODELS.get(value.get("character_model_id", ""), {})
	if options.is_empty() or value.size() != options.size() + 1: return false
	for key in options:
		if not value.get(key) in options[key]: return false
	return true

static func install(sprite: Sprite2D, value: Dictionary) -> bool:
	if not supported(value): return false
	var overlay: Node2D = sprite.get_node_or_null("SemanticAppearance")
	if overlay == null:
		overlay = load("res://scripts/presentation/character_appearance.gd").new()
		overlay.name = "SemanticAppearance"
		overlay.z_index = -1
		sprite.add_child(overlay)
	if overlay.payload == value: return true
	overlay.payload = value.duplicate(true)
	overlay.hair_color = COLORS[value.hair_color_id]
	sprite.set_meta("character_model_id", value.character_model_id)
	pose(sprite, false, 0, 0)
	overlay.queue_redraw()
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
	uniform vec4 hair_color : source_color;
	uniform float bright;
	uniform float sheet_rows;
	uniform bool walking_yuna;
	uniform bool yuna;
	void fragment() {
		vec4 c = texture(TEXTURE, UV);
		float head_y = fract(UV.y * sheet_rows);
		// The authored Yuna walking sheet uses a solid green matte.
		if (walking_yuna && distance(c.rgb, vec3(0.275, 0.435, 0.294)) < 0.06) c.a = 0.0;
		// Pink pixels in the head/hair area of the existing art become the preset.
		if (head_y < 0.31 && ((c.r > c.g * 1.18 && c.b > c.g * 1.06) || (yuna && head_y < 0.25 && c.r > c.g * 1.4 && c.r > c.b * 1.2)) && c.a > 0.0) {
			float shade = clamp((c.r + c.g + c.b) / 2.1, 0.25, 1.3);
			c.rgb = hair_color.rgb * shade;
		} else if (head_y < 0.23 && c.r > c.b * 1.1 && c.r > c.g) {
			c.rgb = mix(c.rgb, vec3(1.0, 0.82, 0.73), bright * 0.3);
		}
		COLOR = c;
	}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("hair_color", COLORS[value.hair_color_id])
	material.set_shader_parameter("sheet_rows", float(sprite.vframes))
	material.set_shader_parameter("walking_yuna", false)
	material.set_shader_parameter("yuna", value.character_model_id == "yuna")
	material.set_shader_parameter("bright", 1.0 if value.face_style_id == "bright" else 0.0)
	sprite.material = material
	sprite.modulate = Color.WHITE
	return true

func _draw() -> void:
	if payload.get("hair_style_id") == "long":
		# Cosmetic strands follow the sprite; no collision, scale or physics change.
		draw_colored_polygon(PackedVector2Array([Vector2(-7,-56), Vector2(-12,-43), Vector2(-13,-22), Vector2(-5,-26), Vector2(-3,-49)]), hair_color)
		draw_colored_polygon(PackedVector2Array([Vector2(6,-56), Vector2(11,-43), Vector2(13,-22), Vector2(5,-26), Vector2(3,-49)]), hair_color)
