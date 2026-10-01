extends Control
## Startup landing scene; world replica/rendering comes in the next patches.

const LOGIN_SCENE := "res://scenes/mmo/login.tscn"
@onready var identity: Label = $Layout/Column/Identity
@onready var status_label: Label = $Layout/Column/Status
@onready var leave_button: Button = $Layout/Column/Leave
var _transition_pending := false

func _ready() -> void:
	leave_button.pressed.connect(_leave_world)
	MmoClient.state_changed.connect(_on_state_changed)
	MmoClient.fault.connect(_on_fault)
	if MmoClient.state != "READY":
		_return_to_login()
		return
	for player in MmoClient.last_snapshot.players:
		if player.player_id == MmoClient.player_id:
			identity.text = "%s · %s" % [player.nickname, MmoClient.map_document.map_id]
			break
	_on_state_changed(MmoClient.state)

func _leave_world() -> void:
	if not MmoClient.logout():
		status_label.text = "The client is busy. Try leaving again in a moment."

func _on_state_changed(value: String) -> void:
	leave_button.disabled = value != "READY"
	if value == "LOGGING_OUT":
		status_label.text = "Leaving world..."
	elif value == "READY":
		status_label.text = "Connected to world."
	elif value in ["FAILED", "DISCONNECTED"]:
		_return_to_login()

func _on_fault(_info: Dictionary) -> void:
	_return_to_login()

func _return_to_login() -> void:
	if not _transition_pending:
		_transition_pending = true
		_change_scene.call_deferred()

func _change_scene() -> void:
	if get_tree().change_scene_to_file(LOGIN_SCENE) != OK:
		_transition_pending = false
		status_label.text = "Cannot open the login scene."
