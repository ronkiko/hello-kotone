extends Node2D
## A single Godot-native animated damage number. No networking or timers.
@onready var label: Label = $Label
@onready var animation: AnimationPlayer = $AnimationPlayer

func show_number(amount: int, world_position: Vector2) -> void:
	global_position = world_position
	label.text = "-%d" % amount
	animation.animation_finished.connect(_on_animation_finished, CONNECT_ONE_SHOT)
	animation.play(&"float_and_fade")

func _on_animation_finished(_name: StringName) -> void:
	queue_free()
