extends Node
## Samples current intent only. No position, accumulated steps or replay queue.
var client: Node
var _require_release := true
var _focused := true

func _ready() -> void:
	client.move_rejected.connect(_on_rejected)
	client.state_changed.connect(_on_state)

func _process(_delta: float) -> void:
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	if not left and not right:
		_require_release = false
		return
	if not _focused or _require_release or left == right or client.state != "READY":
		return
	client.move("left" if left else "right")

func _on_rejected(_code: String) -> void:
	_require_release = true

func _on_state(value: String) -> void:
	if value not in ["READY", "MOVING"]:
		_require_release = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_require_release = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
