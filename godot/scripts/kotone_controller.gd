extends Node2D
## Standalone prototype input; MMO presentation does not attach this controller.
const WALK_SPEED := 102.0
const MIN_X := 65.0
const MAX_X := 417.0
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
var facing := 1
@onready var visual: AnimatedSprite2D = $CharacterVisualLayer/Visual

func _process(delta: float) -> void:
	var left := Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)
	var right := Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)
	var direction := 0 if left == right else -1 if left else 1
	var before := position.x
	position.x = clampf(position.x + direction * WALK_SPEED * delta, MIN_X, MAX_X)
	var moved := not is_equal_approx(position.x, before)
	if moved:
		facing = direction
	visual.play(Appearance.walk_animation(facing) if moved else Appearance.idle_animation(facing))
