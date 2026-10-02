extends Node
## Samples current human locomotion intent only. No position, accumulated steps or replay queue.
signal locomotion_intent_changed(direction: int)
var client: Node
var locomotion_intent := 0
var _require_release := true
var _focused := true

func _ready() -> void:
	client.move_rejected.connect(_on_rejected)
	client.state_changed.connect(_on_state)

func _set_locomotion_intent(value: int) -> void:
	if value == locomotion_intent:
		return
	locomotion_intent = value
	locomotion_intent_changed.emit(value)

func _process(_delta: float) -> void:
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	if not left and not right:
		_require_release = false
		_set_locomotion_intent(0)
		return
	var direction := 0
	if _focused and not _require_release and left != right:
		direction = -1 if left else 1
	_set_locomotion_intent(direction)
	if direction == 0 or client.state != "READY":
		return
	client.move("left" if direction < 0 else "right")

func _on_rejected(_code: String) -> void:
	_require_release = true
	_set_locomotion_intent(0)

func _on_state(value: String) -> void:
	if value not in ["READY", "MOVING"]:
		_require_release = true
		_set_locomotion_intent(0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_require_release = true
		_set_locomotion_intent(0)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
