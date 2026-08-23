extends Node2D


func _on_stand_button_pressed() -> void:
	$AnimationPlayer.play("stand")


func _on_duck_button_pressed() -> void:
	$AnimationPlayer.play("crouch")


func _on_run_button_pressed() -> void:
	$AnimationPlayer.play("run")


func _on_flip_button_pressed() -> void:
	%Pivot.scale.x = -%Pivot.scale.x
	if %Pivot.scale.x > 0:
		%FlipButton.text = "<= Flip"
	else:
		%FlipButton.text = "Flip =>"


func _on_walk_button_pressed() -> void:
	$AnimationPlayer.play("walk")
