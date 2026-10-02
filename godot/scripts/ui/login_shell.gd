extends Control
## Scene presentation only. The persistent MmoClient owns the entire wire flow.

const WORLD_SCENE := "res://scenes/mmo/world.tscn"
const STAGES := {
	"CONNECTING_LOGIN": "Connecting to Login...",
	"AUTHORIZING": "Authorizing nickname...",
	"CONNECTING_GAME": "Connecting to Game...",
	"LOADING_SESSION_RULES": "Loading session policy...",
	"ENTERING_WORLD": "Entering world...",
	"LOADING_MAP": "Loading map...",
	"LOADING_RULES": "Loading world rules...",
	"LOADING_STATE": "Loading world state...",
	"READY": "Ready",
	"RESYNCING": "Refreshing world...",
}
const ERRORS := {
	"CONNECT_FAILED": "Cannot reach the server. Check the address and start the server.",
	"CONNECT_TIMEOUT": "The server did not answer. Check the address and try again.",
	"DNS_FAILED": "Cannot resolve the server address.",
	"INVALID_CONFIG": "Enter a valid server address, port and nickname.",
	"NICKNAME_NOT_ALLOWED": "Nickname rejected. Use player1, player2 or player3.",
	"ALREADY_ONLINE": "This player is already online. Disconnect the other client first.",
	"CANCELLED": "Connection cancelled.",
	"DISCONNECTED": "Connection to the server was lost.",
	"REQUEST_TIMEOUT": "The server took too long to respond.",
	"UNSUPPORTED_VERSION": "Client and server protocol versions do not match.",
	"FLUSH_FAILED": "Logout was rejected: the server could not save the checkpoint.",
	"INVALID_MAP": "Saved world state is incompatible with the server map. Ask the operator to restore or migrate the map.",
	"STREAM_DESYNC": "World updates lost synchronization. Connect again for a fresh world state.",
}
@onready var nickname: LineEdit = $Layout/Column/Fields/Nickname
@onready var host: LineEdit = $Layout/Column/Fields/Host
@onready var port: SpinBox = $Layout/Column/Fields/Port
@onready var status_label: Label = $Layout/Column/Status
@onready var connect_button: Button = $Layout/Column/Actions/Connect
@onready var cancel_button: Button = $Layout/Column/Actions/Cancel
var _transition_pending := false

func _ready() -> void:
	connect_button.pressed.connect(_connect_world)
	cancel_button.pressed.connect(MmoClient.disconnect_world)
	nickname.text_submitted.connect(_submit)
	host.text_submitted.connect(_submit)
	MmoClient.state_changed.connect(_on_state_changed)
	MmoClient.fault.connect(_on_fault)
	MmoClient.world_ready.connect(_on_world_ready)
	var endpoint: Dictionary = MmoClient.login_endpoint
	if not endpoint.is_empty():
		host.text = endpoint.host
		port.value = endpoint.port
		nickname.text = endpoint.nickname
	_on_state_changed(MmoClient.state)
	nickname.grab_focus()
	if MmoClient.state == "READY":
		_on_world_ready()

func _submit(_text: String) -> void:
	_connect_world()

func _connect_world() -> void:
	if connect_button.disabled:
		return
	# Accept a manually typed SpinBox value even when Enter was not pressed.
	port.apply()
	MmoClient.connect_world(host.text.strip_edges(), int(port.value), nickname.text.strip_edges())

func _on_state_changed(value: String) -> void:
	var busy := value not in ["IDLE", "FAILED", "DISCONNECTED"]
	nickname.editable = not busy
	host.editable = not busy
	port.editable = not busy
	connect_button.text = "Reconnect" if value in ["FAILED", "DISCONNECTED"] and not MmoClient.login_endpoint.is_empty() else "Connect"
	connect_button.disabled = busy
	cancel_button.disabled = not busy or value == "READY"
	status_label.modulate = Color("a9c9e8")
	if STAGES.has(value):
		status_label.text = STAGES[value]
	elif value == "FAILED":
		_on_fault(MmoClient.last_error)
	else:
		status_label.text = "Choose a nickname and connect." if value == "IDLE" else "Disconnected. You can connect again."

func _on_fault(info: Dictionary) -> void:
	status_label.modulate = Color("ffb2ad")
	# Never display server error messages, wire payloads, session IDs or tickets.
	status_label.text = ERRORS.get(info.get("code", ""), "The connection failed. Check the server and try again.")
	if info.get("outcome_unknown", false):
		status_label.text += " Server outcome unknown. Reconnect to read server state; the action will not be repeated."

func _on_world_ready() -> void:
	if not _transition_pending:
		_transition_pending = true
		_enter_world.call_deferred()

func _enter_world() -> void:
	_transition_pending = false
	if MmoClient.state != "READY":
		return
	var result := get_tree().change_scene_to_file(WORLD_SCENE)
	if result != OK:
		MmoClient.disconnect_world()
		status_label.text = "Cannot open the world scene."
