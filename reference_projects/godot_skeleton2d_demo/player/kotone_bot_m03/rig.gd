@tool
extends Node2D

# Bone2D.rest is stored separately from the live Node2D transform.
# Apply it once when this isolated rig enters the editor or preview scene.
func _ready() -> void:
	for child in $Skeleton2D.get_children():
		if child is Bone2D:
			_apply_rest_recursive(child)


func _apply_rest_recursive(bone: Bone2D) -> void:
	bone.apply_rest()
	for child in bone.get_children():
		if child is Bone2D:
			_apply_rest_recursive(child)
