## MainMenu — title screen.
##
## Bypass behaviour (checked before any UI is built):
##   --skip-menu     → skip to World
##   headless mode   → skip to World immediately (test runner / CI)
##
## Normal launch → _build_ui() constructs the menu widgets.
extends Control

## Exposed so tests can inspect it after _ready().
## Null when the menu was bypassed (headless / CLI args).
var _name_edit: LineEdit = null

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--skip-menu" in args:
		get_tree().change_scene_to_file.call_deferred("res://world/World.tscn")
		return
	# Also bypass in headless mode (test runner, CI)
	if DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file.call_deferred("res://world/World.tscn")
		return
	# Normal path: build and show the menu UI
	_build_ui()

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

	# Play button
	var play_btn := Button.new()
	play_btn.name = "PlayButton"
	play_btn.text = "Play"
	play_btn.pressed.connect(_on_play_pressed)
	vbox.add_child(play_btn)

func _on_play_pressed() -> void:
	_save_name()
	get_tree().change_scene_to_file("res://world/World.tscn")

func _save_name() -> void:
	if _name_edit != null:
		PlayerIdentity.save_display_name(_name_edit.text)
