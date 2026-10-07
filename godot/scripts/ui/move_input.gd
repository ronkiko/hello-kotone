extends Node
## Human ergonomics only; the server independently bounds semantic controls.
signal locomotion_intent_changed(direction: int)
var client: Node
var locomotion_intent := 0
var facing := 1
var _pressed := 0
var _held_seconds := 0.0
var _require_release := true
var _focused := true
var _engage_ms := 0

func _ready() -> void:
	facing = client.world_replica.local_player().get("motion", {}).get("facing", 1)
	var movement: Dictionary = client.world_rules.get("movement", {})
	_engage_ms = int(movement.get("engage_ms", 0))
	client.input_rejected.connect(_on_rejected)
	client.state_changed.connect(_on_state)

func _submit(drive: int, orientation: int, send: bool = true) -> void:
	if drive == locomotion_intent and orientation == facing: return
	locomotion_intent = drive
	facing = orientation
	locomotion_intent_changed.emit(drive)
	if send and client.state in ["READY", "MOVING"]: client.set_control(drive, facing)

func _physics_process(delta: float) -> void:
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	if not left and not right: _require_release = false
	var direction := 0
	if _focused and not _require_release and left != right and client.state in ["READY", "MOVING"]: direction = -1 if left else 1
	sample_direction(direction, delta)

func sample_direction(direction: int, delta: float) -> void:
	if direction not in [-1, 0, 1]: return
	if direction != _pressed:
		_pressed = direction
		_held_seconds = 0.0
		_submit(0, direction if direction != 0 else facing)
	elif direction != 0:
		_held_seconds += delta
		if _engage_ms > 0 and _held_seconds * 1000.0 + 0.001 >= float(_engage_ms): _submit(direction, facing)

func _on_rejected(_code: String) -> void:
	_require_release = true
	_pressed = 0
	_held_seconds = 0.0
	_submit(0, facing)

func _on_state(value: String) -> void:
	if value not in ["READY", "MOVING"]:
		_require_release = true
		_pressed = 0
		_held_seconds = 0.0
		_submit(0, facing, false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_on_rejected("FOCUS_LOST")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: _focused = true
