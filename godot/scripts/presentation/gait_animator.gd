extends RefCounted
## Presentation reacts to the receiver-relative impact side, never world left/right.
## Physics reports actual mass/velocity contact response, source and receiver facing.
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const BACK_REACTION := &"stumble_back"
const FRONT_REACTION := &"stumble_front"
const MIN_IMPACT_DELTA_MM_S := 300

var cycle_pixels := 24.0
var walk_distance := 0.0
var idle_elapsed := 0.0
var facing := 1
var walking := false
var stop_elapsed := 0.0
const STOP_DEBOUNCE_SECONDS := 0.05
var last_contact_response_tick := 0

static func impact_side(motion: Dictionary) -> StringName:
	var delta_velocity := int(motion.get("contact_delta_velocity_mm_s", 0))
	var response_tick := int(motion.get("contact_response_tick", 0))
	var response_facing := int(motion.get("contact_response_facing", 0))
	var contacts: Variant = motion.get("contact_response_contacts", [])
	var impact_sources: Variant = motion.get("contact_impact_sources", [])
	if response_tick <= 0 or absi(delta_velocity) < MIN_IMPACT_DELTA_MM_S \
		or response_facing not in [-1, 1] or not contacts is Array or contacts.is_empty() \
		or not impact_sources is Array or impact_sources.is_empty():
		return &""
	# A true collision impact in the direction the receiver faces comes from behind.
	# World X is only used to orient/mirror the sprite, not to select its action.
	return &"back" if (delta_velocity > 0) == (response_facing > 0) else &"front"

static func is_contact_reaction(sprite: AnimatedSprite2D) -> bool:
	return sprite != null and sprite.is_playing() \
		and sprite.animation in [BACK_REACTION, FRONT_REACTION]

func configure(value: float) -> void:
	cycle_pixels = maxf(value, 0.001)

func reset(sprite: AnimatedSprite2D, initial_facing: int = 1) -> void:
	walk_distance = 0.0
	idle_elapsed = 0.0
	facing = -1 if initial_facing < 0 else 1
	walking = false
	stop_elapsed = 0.0
	last_contact_response_tick = 0
	Appearance.pose(sprite, false, facing, 0)

func try_contact_reaction(sprite: AnimatedSprite2D, character_model_id: String, motion: Dictionary) -> bool:
	var response_tick := int(motion.get("contact_response_tick", 0))
	if response_tick <= last_contact_response_tick:
		return false
	var side := impact_side(motion)
	if side == &"" or sprite == null or sprite.sprite_frames == null \
		or String(sprite.get_meta("character_model_id", "")) != character_model_id:
		return false
	var reaction: StringName = BACK_REACTION if side == &"back" else FRONT_REACTION
	# Missing front art is an explicit no-animation case, never a back-reaction fallback.
	if not sprite.sprite_frames.has_animation(reaction) \
		or sprite.sprite_frames.get_frame_count(reaction) == 0:
		return false
	last_contact_response_tick = response_tick
	walking = false
	stop_elapsed = 0.0
	idle_elapsed = 0.0
	sprite.stop()
	sprite.animation = reaction
	sprite.flip_h = int(motion.get("contact_response_facing", 1)) < 0
	sprite.set_frame_and_progress(0, 0.0)
	sprite.play()
	return true

func update(sprite: AnimatedSprite2D, before_render_x: float, after_render_x: float,
		authoritative_facing: int, delta: float) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	facing = -1 if authoritative_facing < 0 else 1
	if is_contact_reaction(sprite):
		return
	var displacement := absf(after_render_x - before_render_x)
	var moved := delta > 0.0 and displacement / delta > 1.0
	if moved:
		walking = true
		stop_elapsed = 0.0
		idle_elapsed = 0.0
		walk_distance = fmod(walk_distance + displacement, cycle_pixels)
		var count := Appearance.walk_frame_count(sprite, facing)
		Appearance.pose(sprite, true, facing, int(walk_distance / cycle_pixels * count))
		return
	if walking:
		stop_elapsed += maxf(delta, 0.0)
		if stop_elapsed < STOP_DEBOUNCE_SECONDS: return
		walking = false
		stop_elapsed = 0.0
		idle_elapsed = 0.0
		Appearance.pose(sprite, false, facing, 0)
	idle_elapsed += maxf(delta, 0.0)
	Appearance.pose(sprite, false, facing, Appearance.idle_frame(sprite, idle_elapsed, facing))
