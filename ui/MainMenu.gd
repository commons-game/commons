## MainMenu — title screen with host / join / solo options.
##
## Bypass behaviour (checked before any UI is built):
##   --host          → set GameConfig.mode = "host", skip to World
##   --join <ip>     → set GameConfig.mode = "join", skip to World
##   --skip-menu     → skip to World as solo (GameConfig.mode stays "")
##   headless mode   → skip to World immediately (test runner / CI)
##
## Normal launch → _build_ui() constructs the menu widgets.
##
## _parse_port(args) honours a --port <n> arg shared by --host and --join.
extends Control

## Exposed so tests can inspect it after _ready().
## Null when the menu was bypassed (headless / CLI args).
var _name_edit: LineEdit = null

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# Bypass menu when launched with CLI args (tests, dev tools, --force-day, etc.)
	if "--host" in args:
		PlayerIdentity.display_name = PlayerIdentity.display_name  # already loaded
		GameConfig.mode = "host"
		_parse_port(args)
		get_tree().change_scene_to_file.call_deferred("res://world/World.tscn")
		return
	if "--join" in args:
		var idx := args.find("--join")
		GameConfig.mode = "join"
		GameConfig.host_ip = args[idx + 1] if idx + 1 < args.size() else "127.0.0.1"
		_parse_port(args)
		get_tree().change_scene_to_file.call_deferred("res://world/World.tscn")
		return
	if "--skip-menu" in args:
		get_tree().change_scene_to_file.call_deferred("res://world/World.tscn")
		return
	# Also bypass in headless mode (test runner, CI)
	if DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file.call_deferred("res://world/World.tscn")
		return
	# Normal path: build and show the menu UI
	_build_ui()

## Parse an optional --port <n> argument and write it to GameConfig.port.
func _parse_port(args: Array) -> void:
	var idx := args.find("--port")
	if idx != -1 and idx + 1 < args.size():
		var n := int(args[idx + 1])
		if n > 0:
			GameConfig.port = n

## Build the full menu UI. Only called in normal (non-bypassed) launches.
func _build_ui() -> void:
	# Stretch the root Control to fill the viewport.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Dark background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.05, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Centred VBox
	var vbox := VBoxContainer.new()
	vbox.name = "MenuBox"
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(360, 0)
	vbox.offset_left = -180
	vbox.offset_top  = -160
	add_child(vbox)

	# Title label
	var title := Label.new()
	title.name = "Title"
	title.text = "Freeland"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Separator
	vbox.add_child(HSeparator.new())

	# Name field
	var name_label := Label.new()
	name_label.text = "Your name:"
	vbox.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.placeholder_text = "Enter display name…"
	_name_edit.text = PlayerIdentity.display_name
	vbox.add_child(_name_edit)

	vbox.add_child(HSeparator.new())

	# Solo button
	var solo_btn := Button.new()
	solo_btn.name = "SoloButton"
	solo_btn.text = "Play Solo"
	solo_btn.pressed.connect(_on_solo_pressed)
	vbox.add_child(solo_btn)

	# Host button
	var host_btn := Button.new()
	host_btn.name = "HostButton"
	host_btn.text = "Host Game"
	host_btn.pressed.connect(_on_host_pressed)
	vbox.add_child(host_btn)

	# Join row
	var join_row := HBoxContainer.new()
	vbox.add_child(join_row)

	var ip_edit := LineEdit.new()
	ip_edit.name = "IPEdit"
	ip_edit.placeholder_text = "Host IP…"
	ip_edit.text = "127.0.0.1"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(ip_edit)

	var join_btn := Button.new()
	join_btn.name = "JoinButton"
	join_btn.text = "Join"
	join_btn.pressed.connect(func() -> void: _on_join_pressed(ip_edit.text))
	join_row.add_child(join_btn)

## ---- button handlers -------------------------------------------------------

func _on_solo_pressed() -> void:
	_save_name()
	GameConfig.mode = ""
	get_tree().change_scene_to_file("res://world/World.tscn")

func _on_host_pressed() -> void:
	_save_name()
	GameConfig.mode = "host"
	get_tree().change_scene_to_file("res://world/World.tscn")

func _on_join_pressed(ip: String) -> void:
	_save_name()
	GameConfig.mode = "join"
	GameConfig.host_ip = ip if not ip.is_empty() else "127.0.0.1"
	get_tree().change_scene_to_file("res://world/World.tscn")

func _save_name() -> void:
	if _name_edit != null:
		PlayerIdentity.save_display_name(_name_edit.text)
