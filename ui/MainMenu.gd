## MainMenu — title screen.
##
## Bypass behaviour (checked before any UI is built):
##   --skip-menu     → skip to World
##   headless mode   → skip to World immediately (test runner / CI)
##
## Normal launch → _build_ui() constructs the menu widgets.
## The server URL field (under "Advanced") writes to user://server_config.cfg,
## which World._resolve_proxy_url() reads on the next scene load.
extends Control

const DEFAULT_PROXY_URL  := "ws://127.0.0.1:7510"
const CONFIG_PATH        := "user://server_config.cfg"

## Exposed so tests can inspect after _ready().
var _name_edit:   LineEdit = null
var _server_edit: LineEdit = null
var _status_dot:  ColorRect = null
var _status_label: Label = null
var _play_btn:    Button = null

## Update banner — hidden until version check completes
var _update_banner: HBoxContainer = null
var _update_label: Label = null
var _update_get_btn: Button = null
var _update_dismiss_btn: Button = null
var _update_url: String = ""

## WS probe for connection status
var _probe_ws: WebSocketPeer = null
var _probe_url: String = ""
var _probe_timer: float = 0.0
const PROBE_INTERVAL := 4.0   ## re-check every 4 s

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--skip-menu" in args:
		get_tree().change_scene_to_file.call_deferred("res://world/World.tscn")
		return
	if DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file.call_deferred("res://world/World.tscn")
		return
	_build_ui()
	# Connect ProcessManager signals before deciding whether to probe
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

func _process(delta: float) -> void:
	if _probe_ws == null:
		return
	_probe_ws.poll()
	match _probe_ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_set_status(true)
			_probe_ws.close()
			_probe_ws = null
		WebSocketPeer.STATE_CLOSED:
			_set_status(false)
			_probe_ws = null
	_probe_timer -= delta
	if _probe_timer <= 0.0:
		_probe_timer = PROBE_INTERVAL
		_start_probe()

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
	title.text = "Freeland"
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

	# Server status row
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
	_status_label.text = "  Server: checking…"
	status_row.add_child(_status_label)

	# Advanced toggle
	var adv_btn := Button.new()
	adv_btn.name = "AdvancedToggle"
	adv_btn.text = "▸ Advanced"
	adv_btn.flat = true
	vbox.add_child(adv_btn)

	var adv_box := VBoxContainer.new()
	adv_box.name = "AdvancedBox"
	adv_box.visible = false
	vbox.add_child(adv_box)

	var srv_label := Label.new()
	srv_label.text = "Server URL:"
	adv_box.add_child(srv_label)

	_server_edit = LineEdit.new()
	_server_edit.name = "ServerEdit"
	_server_edit.placeholder_text = DEFAULT_PROXY_URL
	_server_edit.text = _load_saved_url()
	_server_edit.text_changed.connect(_on_server_url_changed)
	adv_box.add_child(_server_edit)

	adv_btn.pressed.connect(func():
		adv_box.visible = not adv_box.visible
		adv_btn.text = ("▾ Advanced" if adv_box.visible else "▸ Advanced"))

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
# Proxy connection probe
# ---------------------------------------------------------------------------

func _start_probe() -> void:
	var url := _current_url()
	if url == _probe_url and _probe_ws != null:
		return
	_probe_url = url
	if _probe_ws != null:
		_probe_ws.close()
	_probe_ws = WebSocketPeer.new()
	var err := _probe_ws.connect_to_url(url)
	if err != OK:
		_probe_ws = null
		_set_status(false)

func _set_status(reachable: bool) -> void:
	if _status_dot == null or _status_label == null:
		return
	if reachable:
		_status_dot.color  = Color(0.2, 0.85, 0.3)   # green
		_status_label.text = "  Server: connected"
	else:
		_status_dot.color  = Color(0.85, 0.2, 0.2)   # red
		_status_label.text = "  Server: unreachable"

# ---------------------------------------------------------------------------
# ProcessManager signal handlers
# ---------------------------------------------------------------------------

func _on_backend_ready() -> void:
	if _play_btn != null:
		_play_btn.disabled = false
	_start_probe()

func _on_backend_failed(reason: String) -> void:
	_set_status(false)
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

func _current_url() -> String:
	if _server_edit != null:
		var typed := _server_edit.text.strip_edges()
		if not typed.is_empty():
			return typed
	return _load_saved_url()

func _load_saved_url() -> String:
	if FileAccess.file_exists(CONFIG_PATH):
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f:
			var stored := f.get_line().strip_edges()
			f.close()
			if not stored.is_empty():
				return stored
	return ""   # empty means "use default"

func _on_server_url_changed(_new_text: String) -> void:
	# Restart probe when URL changes; save on play.
	_probe_timer = 0.0

func _on_play_pressed() -> void:
	_save_name()
	_save_server_url()
	get_tree().change_scene_to_file("res://world/World.tscn")

func _save_name() -> void:
	if _name_edit != null:
		PlayerIdentity.save_display_name(_name_edit.text)

func _save_server_url() -> void:
	if _server_edit == null:
		return
	var url := _server_edit.text.strip_edges()
	var fw := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if fw:
		fw.store_line(url)   # empty string = use default next launch
		fw.close()

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
