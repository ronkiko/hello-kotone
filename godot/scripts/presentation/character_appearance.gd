extends Node2D
## Local hello-kotone semantic mapping, shared by Creator and world avatars.
const OPTIONS := {
	"archetype_id": ["resident"], "body_variant_id": ["standard"],
	"face_style_id": ["soft", "bright"], "hair_style_id": ["short", "long"],
	"hair_color_id": ["chestnut", "black", "silver"],
}
const COLORS := {"chestnut": Color("8c5039"), "black": Color("272534"), "silver": Color("c5d4e2")}
var payload := {}
var hair_color := Color.WHITE
static func supported(value: Variant) -> bool:
	if not value is Dictionary or value.size() != OPTIONS.size(): return false
	for key in OPTIONS:
		if not value.get(key) in OPTIONS[key]: return false
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
	overlay.queue_redraw()
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
	uniform vec4 hair_color : source_color;
	uniform float bright;
	void fragment() {
		vec4 c = texture(TEXTURE, UV);
		// Pink pixels in the head/hair area of the existing art become the preset.
		if (UV.y < 0.31 && c.r > c.g * 1.18 && c.b > c.g * 1.06 && c.a > 0.0) {
			float shade = clamp((c.r + c.g + c.b) / 2.1, 0.25, 1.3);
			c.rgb = hair_color.rgb * shade;
		} else if (UV.y < 0.23 && c.r > c.b * 1.1 && c.r > c.g) {
			c.rgb = mix(c.rgb, vec3(1.0, 0.82, 0.73), bright * 0.3);
		}
		COLOR = c;
	}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("hair_color", COLORS[value.hair_color_id])
	material.set_shader_parameter("bright", 1.0 if value.face_style_id == "bright" else 0.0)
	sprite.material = material
	sprite.modulate = Color.WHITE
	return true

func _draw() -> void:
	if payload.get("hair_style_id") == "long":
		# Cosmetic strands follow the sprite; no collision, scale or physics change.
		draw_colored_polygon(PackedVector2Array([Vector2(-7,-56), Vector2(-12,-43), Vector2(-13,-22), Vector2(-5,-26), Vector2(-3,-49)]), hair_color)
		draw_colored_polygon(PackedVector2Array([Vector2(6,-56), Vector2(11,-43), Vector2(13,-22), Vector2(5,-26), Vector2(3,-49)]), hair_color)
