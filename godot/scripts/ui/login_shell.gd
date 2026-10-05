extends Control
## Human pre-world shell; only safe public labels enter the UI.
const WORLD_SCENE := "res://scenes/mmo/world.tscn"
const Appearance = preload("res://scripts/presentation/character_appearance.gd")
const Kotone = preload("res://scenes/kotone.tscn")
const ERRORS := {
	"PENDING_OPERATION_LIMIT": "Reconcile a pending character operation before starting another.",
	"AUTH_FAILED": "Sign-in failed. Check your account and password.",
	"REAUTH_REQUIRED": "Sign in again to choose a realm.",
	"NAME_TAKEN": "That character name is taken.",
	"SLOTS_FULL": "All character slots are occupied.",
	"APPEARANCE_INVALID": "The server rejected these appearance options.",
	"APPEARANCE_INCOMPATIBLE": "This appearance needs an updated client.",
	"CHARACTER_BUSY": "This character still has a world visit in progress.",
	"DURABILITY_UNSAFE": "The character's last save is not confirmed. Ask the operator to reconcile it.",
	"RATE_LIMITED": "Please wait before trying again.",
	"FLUSH_FAILED": "The world save was not confirmed.",
	"REGISTRY_UNAVAILABLE": "The character roster is temporarily unavailable.",
	"IDEMPOTENCY_LIMIT": "This account has reached its character operation limit.",
	"STALE_CHARACTER": "The character changed. Refresh and select it again.",
	"REALM_UNAVAILABLE": "That realm is unavailable.",
	"INVALID_CONFIG": "Check the address, port and account.",
	"INSECURE_REMOTE_FORBIDDEN": "Remote servers require a secure connection.",
	"TLS_FAILED": "The secure connection could not be verified.",
}
var column: VBoxContainer
var status_label: Label
var nickname: LineEdit
var password: LineEdit
var host: LineEdit
var port: SpinBox
var security: OptionButton
var ca_path: LineEdit
var creator_name_edit: LineEdit
var creator_choices := {}
var creator_name := ""
var creator_payload := {}
var preview: Sprite2D
var _page := ""
var _transition_pending := false

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("111b27")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 18
	scroll.offset_right = -18
	scroll.offset_top = 8
	scroll.offset_bottom = -8
	add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	scroll.add_child(column)
	Preworld.changed.connect(_render)
	MmoClient.world_ready.connect(_world_ready)
	MmoClient.state_changed.connect(_game_state)
	_render()

func _label(text: String, size: int = 12) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(node)
	return node

func _button(text: String, action: Callable, enabled: bool = true) -> Button:
	var node := Button.new()
	node.text = text
	node.disabled = not enabled
	node.pressed.connect(action)
	column.add_child(node)
	return node

func _field(caption: String, text: String, secret: bool = false) -> LineEdit:
	var row := HBoxContainer.new()
	column.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 110
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = text
	edit.secret = secret
	edit.max_length = 128 if secret else 253
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit

func _render() -> void:
	if column == null: return
	var state: String = Preworld.state
	var page := state if state in ["LOGIN", "REALMS", "LOBBY", "CREATOR", "FAILED"] else "LOADING"
	if page == "LOADING" or page != _page or page in ["LOBBY", "REALMS"]:
		_page = page
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
		_label("HELLO, KOTONE", 20)
		match page:
			"LOGIN": _login_page()
			"REALMS": _realm_page()
			"LOBBY": _lobby_page()
			"CREATOR": _creator_page()
			"FAILED": _failure_page()
			_: _label("Connecting…" if state != "WORLD" else "Loading world…")
		status_label = _label("")
	if not Preworld.error.is_empty():
		var info: Dictionary = Preworld.error
		status_label.text = "%s: %s" % [info.phase, ERRORS.get(info.code, "The request failed. Refresh or sign in again.")]
		if info.get("outcome_unknown", false):
			status_label.text += " Outcome unknown. Nothing will be repeated automatically."
	else:
		status_label.text = state.capitalize().replace("_", " ") if page == "LOADING" else ""

func _login_page() -> void:
	_label("Account sign-in")
	var row := HBoxContainer.new()
	column.add_child(row)
	security = OptionButton.new()
	security.add_item("Local development")
	security.add_item("Secure server")
	security.select(1 if Preworld.profile == "internet_beta" else 0)
	row.add_child(security)
	nickname = _field("Account", Preworld.username)
	password = _field("Password", "", true)
	password.get_parent().visible = security.selected == 1
	host = _field("Login address", Preworld.login_endpoint.host)
	var ports := HBoxContainer.new()
	column.add_child(ports)
	var label := Label.new()
	label.text = "Port"
	label.custom_minimum_size.x = 110
	ports.add_child(label)
	port = SpinBox.new()
	port.min_value = 1
	port.max_value = 65535
	port.value = Preworld.login_endpoint.port
	ports.add_child(port)
	ca_path = _field("Local test CA", "")
	ca_path.placeholder_text = "Optional PEM certificate for a local TLS rehearsal"
	ca_path.get_parent().visible = security.selected == 1
	security.item_selected.connect(func(index: int):
		password.get_parent().visible = index == 1
		ca_path.get_parent().visible = index == 1)
	_button("Sign in", _login)
	password.text_submitted.connect(func(_text: String): _login())
	nickname.text_submitted.connect(func(_text: String): _login())
	nickname.grab_focus()

func _login() -> void:
	port.apply()
	var ca: X509Certificate
	if security.selected == 1 and not ca_path.text.strip_edges().is_empty():
		ca = X509Certificate.new()
		if ca.load(ca_path.text.strip_edges()) != OK:
			status_label.text = "Cannot load the local test certificate."
			return
	var secret := password.text
	password.text = ""
	Preworld.login(host.text.strip_edges(), int(port.value), nickname.text.strip_edges(), secret,
		"internet_beta" if security.selected == 1 else "trusted_local_dev", ca)
	secret = ""

func _realm_page() -> void:
	_label("Choose a realm", 16)
	for index in range(Preworld.realms.size()):
		var realm: Dictionary = Preworld.realms[index]
		_button("%s · %s" % [realm.display_name, realm.status], Preworld.select_realm.bind(index), realm.status == "online" and realm.game_card_id == "hello-kotone")
	_button("Sign out", Preworld.logout_account)

func _lobby_page() -> void:
	_label("%s · Characters %d/%d" % [Preworld.realm.display_name, Preworld.roster.get("characters", []).size(), Preworld.roster.get("slot_limit", 0)], 16)
	for record in Preworld.roster.get("characters", []):
		_button("%d. %s" % [record.slot, record.display_name], Preworld.select_character.bind(record.character_id))
	if not Preworld.selection.is_empty():
		var record: Dictionary = Preworld.selection.character
		_label("Selected: " + record.display_name)
		_preview(Preworld.catalog.default_payload if record.appearance_payload.is_empty() else record.appearance_payload)
		_button("Enter world", Preworld.enter_world, Preworld.availability.get("status") == "online")
		_button("Delete character…", _confirm_delete, not Preworld.mutation_pending)
	_button("Create character", _open_creator, not Preworld.catalog.is_empty() and Preworld.roster.get("characters", []).size() < Preworld.roster.get("slot_limit", 0) and not Preworld.mutation_pending)
	if Preworld.mutation_pending:
		_button("Reconcile pending character operation", Preworld.reconcile_mutation)
	_button("Refresh roster", Preworld.refresh_roster)
	_button("Back to realms", Preworld.back_to_realms)
	_button("Sign out", Preworld.logout_account)

func _confirm_delete() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Delete %s? This permanently removes the character." % Preworld.selection.character.display_name
	add_child(dialog)
	dialog.confirmed.connect(Preworld.delete_selected)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _open_creator() -> void:
	creator_payload = Preworld.catalog.default_payload.duplicate(true)
	creator_name = ""
	Preworld.show_creator()

func _creator_page() -> void:
	_label("Create a character", 16)
	creator_name_edit = _field("Name", creator_name)
	creator_name_edit.max_length = 64
	creator_name_edit.text_changed.connect(func(text: String): creator_name = text)
	var row := HBoxContainer.new()
	column.add_child(row)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(choices)
	creator_choices = {}
	for key in Preworld.catalog.options:
		var options: Array = Preworld.catalog.options[key]
		if options.size() == 1: continue
		var option_row := HBoxContainer.new()
		choices.add_child(option_row)
		var caption := Label.new()
		caption.text = key.trim_suffix("_id").replace("_", " ").capitalize()
		caption.custom_minimum_size.x = 100
		option_row.add_child(caption)
		var choice := OptionButton.new()
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option_row.add_child(choice)
		creator_choices[key] = choice
		for option in options: choice.add_item(option.capitalize())
		choice.select(options.find(creator_payload.get(key)))
		choice.item_selected.connect(func(index: int):
			creator_payload[key] = options[index]
			Appearance.install(preview, creator_payload))
	_preview(creator_payload, row)
	_button("Create", func(): Preworld.create_character(creator_name, creator_payload), Appearance.supported(creator_payload))
	_button("Back to characters", Preworld.refresh_roster)

func _preview(payload: Dictionary, parent: Node = null) -> void:
	var frame := SubViewportContainer.new()
	frame.custom_minimum_size = Vector2(110, 88)
	(column if parent == null else parent).add_child(frame)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(110, 88)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	frame.add_child(viewport)
	preview = Kotone.instantiate()
	preview.set_script(null)
	preview.position = Vector2(55, 43)
	preview.scale = Vector2(0.64, 0.64)
	viewport.add_child(preview)
	Appearance.install(preview, payload)

func _failure_page() -> void:
	_label("Connection interrupted", 16)
	if Preworld.error.get("phase") == "Game":
		_button("Return to realm lobby", Preworld.return_to_lobby)
	_button("Sign in again", Preworld.logout_account)

func _game_state(_state: String) -> void:
	if Preworld.state == "WORLD": _render()

func _world_ready() -> void:
	if _transition_pending: return
	_transition_pending = true
	_enter_world.call_deferred()

func _enter_world() -> void:
	_transition_pending = false
	if MmoClient.state == "READY" and Preworld.state == "WORLD":
		get_tree().change_scene_to_file(WORLD_SCENE)
