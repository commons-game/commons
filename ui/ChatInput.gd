## ChatInput — text input bar for chat. Activated by Enter, dismissed by Esc.
##
## CanvasLayer at layer 20. Invisible by default.
## World sets `player` reference after adding to scene tree.
##
## Usage:
##   var chat_input := ChatInputScript.new()
##   add_child(chat_input)
##   chat_input.player = $Player
extends CanvasLayer

## Set by World after instantiation.
var player: Node = null

var _line_edit: LineEdit = null

func _init() -> void:
	layer = 20

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	var panel := Panel.new()
	panel.name = "InputBG"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_CENTER)
	panel.custom_minimum_size = Vector2(480, 32)
	panel.size = Vector2(480, 32)
	panel.position = Vector2(-240, -40)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.85)
	style.border_width_bottom = 1
	style.border_width_top    = 1
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_color = Color(0.4, 0.5, 0.8, 0.9)
	style.corner_radius_bottom_left  = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_top_left     = 3
	style.corner_radius_top_right    = 3
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	_line_edit = LineEdit.new()
	_line_edit.name = "LineEdit"
	_line_edit.placeholder_text = "Type to chat... /dm <name> <msg>  /addfriend <name>"
	_line_edit.set_anchors_preset(Control.PRESET_FULL_RECT)
	_line_edit.offset_left   = 6
	_line_edit.offset_top    = 2
	_line_edit.offset_right  = -6
	_line_edit.offset_bottom = -2
	_line_edit.add_theme_font_size_override("font_size", 13)
	_line_edit.add_theme_color_override("font_color", Color(1, 1, 1))
	panel.add_child(_line_edit)

	_line_edit.text_submitted.connect(_on_text_submitted)
	_line_edit.gui_input.connect(_on_line_edit_input)

func activate() -> void:
	visible = true
	_line_edit.clear()
	_line_edit.grab_focus()

func deactivate() -> void:
	visible = false
	_line_edit.release_focus()

func _on_text_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if not trimmed.is_empty():
		var player_id: String = ""
		var player_name: String = ""
		if player != null:
			player_id = str(player.get("id") if player.get("id") != null else PlayerIdentity.id)
			player_name = str(player.get("display_name") if player.get("display_name") != null else PlayerIdentity.id)
		else:
			player_id = PlayerIdentity.id
			player_name = PlayerIdentity.id
		ChatSystem.handle_input(trimmed, player_id, player_name)
	deactivate()
	get_viewport().set_input_as_handled()

func _on_line_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			deactivate()
			get_viewport().set_input_as_handled()
