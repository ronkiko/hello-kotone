extends RefCounted
## Native SpriteFrames microloop; roots/anchors and source resources stay intact.
var original: SpriteFrames
var animation: StringName
var frame := 0
var progress := 0.0
var playing := false

func freeze(sprite: AnimatedSprite2D) -> void:
	if original != null or sprite.sprite_frames == null: return
	original = sprite.sprite_frames
	animation = sprite.animation
	frame = sprite.frame
	progress = sprite.frame_progress
	playing = sprite.is_playing()
	var count := original.get_frame_count(animation)
	if count < 3:
		sprite.pause()
		return
	var tiny := SpriteFrames.new()
	tiny.add_animation(&"stall")
	tiny.set_animation_loop(&"stall", true)
	tiny.set_animation_speed(&"stall", original.get_animation_speed(animation))
	var length := mini(4, count - 1)
	var start := mini(frame, count - length)
	for index in range(start, start + length):
		tiny.add_frame(&"stall", original.get_frame_texture(animation, index), original.get_frame_duration(animation, index))
	sprite.sprite_frames = tiny
	sprite.play(&"stall")
	sprite.set_frame_and_progress(frame - start, progress)

func thaw(sprite: AnimatedSprite2D) -> void:
	if original == null: return
	sprite.sprite_frames = original
	sprite.animation = animation
	sprite.set_frame_and_progress(frame, progress)
	if playing: sprite.play()
	else: sprite.pause()
	original = null
