extends Node2D

@onready var skeleton: Skeleton2D = $Rig/Skeleton2D

var _phase := 0.0


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * 4.2, TAU)
	var near_pose := _sample_leg(_phase / TAU)
	var far_pose := _sample_leg(fposmod(_phase / TAU + 0.5, 1.0))
	var stride := sin(_phase)
	set_bone("Hip", deg_to_rad(stride * 1.2))
	set_bone("Hip/ArmFar", deg_to_rad(-stride * 12.0))
	set_bone("Hip/ArmNear", deg_to_rad(stride * 12.0))
	set_bone("Hip/NearLeg", deg_to_rad(near_pose.x))
	set_bone("Hip/NearLeg/NearLower", deg_to_rad(near_pose.y))
	set_bone("Hip/NearLeg/NearLower/NearFoot", deg_to_rad(-near_pose.x - near_pose.y * 0.65))
	set_bone("Hip/FarLeg", deg_to_rad(far_pose.x))
	set_bone("Hip/FarLeg/FarLower", deg_to_rad(far_pose.y))
	set_bone("Hip/FarLeg/FarLower/FarFoot", deg_to_rad(-far_pose.x - far_pose.y * 0.65))


func _sample_leg(cycle: float) -> Vector2:
	if cycle < 0.25:
		var contact_t := smoothstep(0.0, 0.25, cycle)
		return Vector2(lerpf(-10.0, -2.0, contact_t), 0.0)
	if cycle < 0.5:
		var stance_t := smoothstep(0.25, 0.5, cycle)
		return Vector2(lerpf(-2.0, 10.0, stance_t), 0.0)
	if cycle < 0.75:
		var lift_t := smoothstep(0.5, 0.75, cycle)
		return Vector2(lerpf(10.0, -15.0, lift_t), lerpf(0.0, 28.0, lift_t))
	var landing_t := smoothstep(0.75, 1.0, cycle)
	return Vector2(lerpf(-15.0, -10.0, landing_t), lerpf(28.0, 0.0, landing_t))


func set_bone(path: String, angle: float) -> void:
	var bone := skeleton.get_node(path) as Bone2D
	bone.rotation = angle
