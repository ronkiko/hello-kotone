extends Node2D

const LEFT_ANGLE := deg_to_rad(-10.0)
const REST_ANGLE := 0.0
const RIGHT_ANGLE := deg_to_rad(10.0)

@onready var head: Bone2D = $Rig/Skeleton2D/Torso/Head
@onready var instruction: Label = $Instruction


func _ready() -> void:
	_set_angle(REST_ANGLE)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_Q:
			_set_angle(LEFT_ANGLE)
		KEY_R:
			_set_angle(REST_ANGLE)
		KEY_E:
			_set_angle(RIGHT_ANGLE)


func _set_angle(angle: float) -> void:
	head.rotation = angle
	instruction.text = "KTN-RC3-M03  STEP 2/6: HEAD  |  Q -10 deg  R REST  E +10 deg  |  current: %.1f deg" % rad_to_deg(angle)
