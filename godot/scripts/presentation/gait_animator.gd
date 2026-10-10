extends RefCounted
## Shared pose cursor driven by rendered displacement and authoritative facing.
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const PUSH_REACTION := &"stumble_right2"
const MIN_PUSH_DELTA_MM_S := 300

var cycle_pixels := 24.0
var walk_distance := 0.0
var idle_elapsed := 0.0
var facing := 1
var walking := false
var stop_elapsed := 0.0
const STOP_DEBOUNCE_SECONDS := 0.05
var last_contact_response_tick := 0

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
	var delta_velocity := int(motion.get("contact_delta_velocity_mm_s", 0))
	var response_tick := int(motion.get("contact_response_tick", 0))
	var response_facing := int(motion.get("contact_response_facing", 0))
	var contacts: Variant = motion.get("contact_response_contacts", [])
	var shove_sources: Variant = motion.get("contact_shove_sources", [])
	if response_tick <= last_contact_response_tick or delta_velocity < MIN_PUSH_DELTA_MM_S \
		or response_facing != 1 or not contacts is Array or contacts.is_empty() \
		or not shove_sources is Array or shove_sources.is_empty():
		return false
	if character_model_id != "yuna" or sprite == null or sprite.sprite_frames == null \
		or not sprite.sprite_frames.has_animation(PUSH_REACTION) \
		or sprite.sprite_frames.get_frame_count(PUSH_REACTION) == 0:
		return false
	# Every distinct authoritative knockback tick is a distinct presentation event.
	# A later impact may restart the non-looping reaction even if the previous one
	# has not quite finished; duplicate delivery of the same server tick stays inert.
	last_contact_response_tick = response_tick
	walking = false
	stop_elapsed = 0.0
	idle_elapsed = 0.0
	sprite.stop()
	sprite.animation = PUSH_REACTION
	sprite.set_frame_and_progress(0, 0.0)
	sprite.play()
	return true

func update(sprite: AnimatedSprite2D, before_render_x: float, after_render_x: float,
		authoritative_facing: int, delta: float) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	facing = -1 if authoritative_facing < 0 else 1
	if sprite.animation == PUSH_REACTION and sprite.is_playing():
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
