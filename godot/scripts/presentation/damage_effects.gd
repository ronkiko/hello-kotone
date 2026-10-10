extends Node2D
## One world-owned cosmetic presenter built from reusable Godot PackedScenes.
const NUMBER_SCENE: PackedScene = preload("res://scenes/mmo/damage_number.tscn")
var display_enabled := true

func _ready() -> void:
	display_enabled = bool(ProjectSettings.get_setting("presentation/damage_numbers_enabled", true))

func show_damage(amount: int, world_position: Vector2) -> void:
	if not display_enabled or amount <= 0:
		return
	var number: Node2D = NUMBER_SCENE.instantiate()
	add_child(number)
	number.call(&"show_number", amount, world_position)

func clear() -> void:
	for effect in get_children():
		effect.queue_free()
