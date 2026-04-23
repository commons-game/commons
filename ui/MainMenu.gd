## MainMenu — title screen.
##
## Bypass behaviour (checked before any UI is built):
##   --skip-menu     → skip to World
##   headless mode   → skip to World immediately (test runner / CI)
##
## Normal launch → _build_ui() constructs the menu widgets.
extends Control

## Exposed so tests can inspect after _ready().
var _name_edit:   LineEdit = null
var _status_dot:  ColorRect = null
var _status_label: Label = null
var _play_btn:    Button = null

## Update banner — hidden until version check completes
var _update_banner: HBoxContainer = null
var _update_label: Label = null
var _update_get_btn: Button = null
var _update_dismiss_btn: Button = null
var _update_url: String = ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--skip-menu" in args:
		get_tree().change_scene_to_file.call_deferred("res://world/World.tscn")
		return
	if DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file.call_deferred("res://world/World.tscn")
		return
	# Puppet scenarios (headless or under xvfb) must bypass the menu so
	# the scenario can drive World directly.
	for a in args:
		if typeof(a) == TYPE_STRING and (a as String).begins_with("--puppet-scenario="):
			get_tree().change_scene_to_file.call_deferred("res://world/World.tscn")
			return
	_build_ui()
	# Connect ProcessManager signals
	ProcessManager.backend_ready.connect(_on_backend_ready)
	ProcessManager.backend_failed.connect(_on_backend_failed)
	ProcessManager.status_changed.connect(_on_backend_status)
	if ProcessManager.is_ready:
		_on_backend_ready()
	# Non-blocking version check (skip in headless mode)
	if DisplayServer.get_name() != "headless":
		_check_for_update.call_deferred()
	# Show consent prompt on first non-headless launch
	if ErrorReporter.needs_consent_prompt():
		var ConsentOverlayScript: GDScript = load("res://ui/ConsentOverlay.gd")
		var overlay: Control = ConsentOverlayScript.new()
		add_child(overlay)
		overlay.connect("accepted", func(): ErrorReporter.set_consent(true))
		overlay.connect("declined", func(): ErrorReporter.set_consent(false))

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.05, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.name = "MenuBox"
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.offset_left = -190
	vbox.offset_top  = -200
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Commons"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Name field
	var name_label := Label.new()
	name_label.text = "Your name:"
	vbox.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.placeholder_text = "Enter display name…"
	_name_edit.text = PlayerIdentity.display_name
	_name_edit.max_length = 20
	vbox.add_child(_name_edit)

	vbox.add_child(HSeparator.new())

	# ProcessManager status row
	var status_row := HBoxContainer.new()
	status_row.name = "StatusRow"
	vbox.add_child(status_row)

	_status_dot = ColorRect.new()
	_status_dot.name = "StatusDot"
	_status_dot.custom_minimum_size = Vector2(12, 12)
	_status_dot.color = Color(0.4, 0.4, 0.4)  # grey = unknown
	status_row.add_child(_status_dot)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "  Backend: starting…"
	status_row.add_child(_status_label)

	vbox.add_child(HSeparator.new())

	# Play button — disabled until ProcessManager confirms backend is ready
	_play_btn = Button.new()
	_play_btn.name = "PlayButton"
	_play_btn.text = "Play"
	_play_btn.disabled = true
	_play_btn.pressed.connect(_on_play_pressed)
	vbox.add_child(_play_btn)

	# Update banner — hidden until version check completes
	_build_update_banner(vbox)

# ---------------------------------------------------------------------------
# ProcessManager signal handlers
# ---------------------------------------------------------------------------

func _on_backend_ready() -> void:
	if _play_btn != null:
		_play_btn.disabled = false
	if _status_dot != null:
		_status_dot.color = Color(0.2, 0.85, 0.3)   # green
	if _status_label != null:
		_status_label.text = "  Backend: ready"

func _on_backend_failed(reason: String) -> void:
	if _status_dot != null:
		_status_dot.color = Color(0.85, 0.2, 0.2)   # red
	if _status_label != null:
		_status_label.text = "  " + reason

func _on_backend_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = "  " + message
	if _status_dot != null:
		_status_dot.color = Color(0.9, 0.7, 0.1)  # yellow = starting

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _on_play_pressed() -> void:
	_save_name()
	get_tree().change_scene_to_file("res://world/World.tscn")

func _save_name() -> void:
	if _name_edit != null:
		PlayerIdentity.save_display_name(_name_edit.text)

# ---------------------------------------------------------------------------
# Update banner
# ---------------------------------------------------------------------------

func _build_update_banner(parent: VBoxContainer) -> void:
	_update_banner = HBoxContainer.new()
	_update_banner.name = "UpdateBanner"
	_update_banner.visible = false
	parent.add_child(_update_banner)

	_update_label = Label.new()
	_update_label.name = "UpdateLabel"
	_update_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_banner.add_child(_update_label)

	_update_get_btn = Button.new()
	_update_get_btn.name = "GetUpdateButton"
	_update_get_btn.text = "Get update"
	_update_get_btn.pressed.connect(func(): OS.shell_open(_update_url))
	_update_banner.add_child(_update_get_btn)

	_update_dismiss_btn = Button.new()
	_update_dismiss_btn.name = "DismissButton"
	_update_dismiss_btn.text = "×"
	_update_dismiss_btn.pressed.connect(func(): _update_banner.visible = false)
	_update_banner.add_child(_update_dismiss_btn)

func _show_update_banner(message: String, url: String, dismissable: bool) -> void:
	if _update_banner == null:
		return
	_update_url = url
	_update_label.text = message
	_update_get_btn.visible = not url.is_empty()
	_update_dismiss_btn.visible = dismissable
	_update_banner.visible = true

func _check_for_update() -> void:
	var backend := get_node_or_null("/root/Backend")
	if backend == null or not backend.has_method("get_version_manifest"):
		return
	var manifest: Dictionary = await backend.get_version_manifest()
	if manifest.is_empty():
		return
	var their_version: String = manifest.get("version", "")
	var our_version: String = GameVersion.GAME_VERSION
	var min_proto: int = manifest.get("min_protocol_version", 0)
	var download_url: String = manifest.get("download_url", "")

	# Safety check: only show banner for github.com URLs
	if not download_url.begins_with("https://github.com/"):
		return

	var is_hard_update: bool = min_proto > GameVersion.PROTOCOL_VERSION
	var is_soft_update: bool = (not their_version.is_empty()) and (their_version != our_version) and (not is_hard_update)

	if is_hard_update:
		_show_update_banner("Update required to join multiplayer games — v%s available" % their_version, download_url, false)
	elif is_soft_update:
		_show_update_banner("v%s available" % their_version, download_url, true)
