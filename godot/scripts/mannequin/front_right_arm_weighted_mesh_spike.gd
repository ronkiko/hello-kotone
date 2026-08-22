extends Node2D

const RIGID_ARM_SPRITES := [
	"BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/UpperArmRight",
	"BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right/ForearmRight",
	"BaseRig/Skeleton2D/pelvis/torso/upper_arm_right/forearm_right/hand_right/HandRight"
]

func _ready() -> void:
	for path in RIGID_ARM_SPRITES:
		var sprite := get_node_or_null(path) as Sprite2D
		if sprite != null:
			sprite.visible = false
