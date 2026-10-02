extends Control
## Read-only world presentation. All confirmed data comes from WorldReplica.

const Platform = preload("res://scripts/presentation/platform_world.gd")
const InputAdapter = preload("res://scripts/ui/move_input.gd")
const Prediction = preload("res://scripts/presentation/local_prediction.gd")
var prediction := Prediction.new()
var input_adapter: Node
var platform: Node2D
const LOGIN_SCENE := "res://scenes/mmo/login.tscn"
@onready var identity: Label = $Layout/Column/Identity
@onready var status_label: Label = $Layout/Column/Status
@onready var leave_button: Button = $Layout/Column/Leave
@onready var refresh_button: Button = $Layout/Column/Refresh
@onready var position_label: Label = $Layout/Column/Position
var _transition_pending := false

func _ready() -> void:
	leave_button.pressed.connect(_leave_world)
	refresh_button.pressed.connect(MmoClient.request_state)
	MmoClient.state_changed.connect(_on_state_changed)
	MmoClient.fault.connect(_on_fault)
	MmoClient.move_rejected.connect(_on_move_rejected)
	MmoClient.move_intended.connect(_on_move_intended)
	MmoClient.world_replica.changed.connect(_show_world)
	MmoClient.world_replica.local_moved.connect(_on_local_moved)
	if MmoClient.state != "READY":
		_return_to_login()
		return
	platform = Platform.new()
	$Layout/Column/View/SubViewport.add_child(platform)
	input_adapter = InputAdapter.new()
	input_adapter.client = MmoClient
	add_child(input_adapter)
	_show_world()
	_on_state_changed(MmoClient.state)

func _show_world() -> void:
	if platform != null:
		platform.set_suspended(MmoClient.world_replica.view().status != "SYNCED")
	var player: Dictionary = MmoClient.world_replica.local_player()
	if player.is_empty():
		prediction.clear()
		identity.text = ""
		position_label.text = ""
		return
	identity.text = "%s · %s" % [player.nickname, player.zone_id]
	position_label.text = "Position: %d" % player.x
	if platform != null:
		var rules: Dictionary = MmoClient.world_rules
		prediction.observe(MmoClient.map_document, MmoClient.world_replica.view(), rules.get("movement", {}).get("step_units", 0))
		_project_display()

func _project_display() -> void:
	if platform != null:
		platform.project(MmoClient.map_document, MmoClient.world_replica.view(), prediction.view().target_x)

func _on_move_intended(direction: String) -> void:
	if prediction.begin(direction):
		_project_display()

func _on_local_moved() -> void:
	# Even a fact with unchanged X resolves speculation. Remote facts do not.
	prediction.reconcile()
	_project_display()

func _leave_world() -> void:
	if not MmoClient.logout():
		status_label.text = "The client is busy. Try leaving again in a moment."

func _on_state_changed(value: String) -> void:
	if value != "MOVING":
		prediction.reconcile()
		_project_display()
	leave_button.disabled = value != "READY"
	refresh_button.disabled = value != "READY"
	if value == "LOGGING_OUT":
		status_label.text = "Leaving world..."
	elif value == "READY":
		status_label.text = "A/D or arrows to walk."
	elif value == "MOVING":
		status_label.text = "A/D or arrows to walk."
	elif value == "RESYNCING":
		status_label.text = "Refreshing world..."
	elif value in ["FAILED", "DISCONNECTED"]:
		_return_to_login()

func _on_move_rejected(code: String) -> void:
	prediction.reconcile()
	_project_display()
	match code:
		"OUT_OF_BOUNDS": status_label.text = "World boundary reached."
		"RATE_LIMITED": status_label.text = "Moving too quickly. Release the key and try again."
		"WORLD_PAUSED": status_label.text = "World paused. Release the key and try later."

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
