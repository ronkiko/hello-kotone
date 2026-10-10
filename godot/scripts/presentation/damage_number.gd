extends Label
## One Godot-native animated number. No network, physics, queue or timer.
@onready var animation: AnimationPlayer = $AnimationPlayer

func show_number(amount: int, world_position: Vector2) -> void:
	text = "-%d" % amount
	global_position = world_position + Vector2(-36, -28)
	animation.animation_finished.connect(_on_animation_finished, CONNECT_ONE_SHOT)
	animation.play(&"float_and_fade")

func _on_animation_finished(_name: StringName) -> void:
	queue_free()
