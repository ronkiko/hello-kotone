extends Sprite2D

const IDLE_FRONT := 0
const WALK_LEFT := 1
const WALK_RIGHT := 2

const IDLE_FRAME_DURATION := 0.3
const WALK_FRAME_DURATION := 0.12
const WALK_SPEED := 102.0
const MIN_X := 65.0
const MAX_X := 417.0

const IDLE_FRONT_TEXTURE := preload("res://assets/kotone_v2_idle_front.png")
const WALK_LEFT_TEXTURE := preload("res://assets/kotone_v2_walking_left.png")
const WALK_RIGHT_TEXTURE := preload("res://assets/kotone_v2_walking_right.png")

var _animation_state := IDLE_FRONT
var _elapsed := 0.0


func _process(delta: float) -> void:
	var direction := _horizontal_input()
	if direction != 0.0:
		position.x = clampf(position.x + direction * WALK_SPEED * delta, MIN_X, MAX_X)
		_set_animation(WALK_LEFT if direction < 0.0 else WALK_RIGHT)
	else:
		_set_animation(IDLE_FRONT)

	_elapsed += delta
	var frame_duration := IDLE_FRAME_DURATION if _animation_state == IDLE_FRONT else WALK_FRAME_DURATION
	frame = int(_elapsed / frame_duration) % hframes


func _horizontal_input() -> float:
	var move_left := Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)
	var move_right := Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)
	if move_left == move_right:
		return 0.0
	return -1.0 if move_left else 1.0


func _set_animation(next_state: int) -> void:
	if _animation_state == next_state:
		return

	_animation_state = next_state
	_elapsed = 0.0
	frame = 0
	match _animation_state:
		IDLE_FRONT:
			texture = IDLE_FRONT_TEXTURE
		WALK_LEFT:
			texture = WALK_LEFT_TEXTURE
		WALK_RIGHT:
			texture = WALK_RIGHT_TEXTURE
