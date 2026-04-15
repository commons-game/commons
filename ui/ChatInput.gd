## ChatInput — text input bar for chat. Activated by T, dismissed by Esc or Enter.
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
	hide()
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.name = "InputBG"
	bg.color = Color(0.05, 0.05, 0.1, 0.88)
	bg.position = Vector2((1280 - 480) / 2, 720 - 50)
	bg.size = Vector2(480, 36)
	# Prevent the bg rect from consuming input events when hidden.
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.focus_mode   = Control.FOCUS_NONE
	add_child(bg)

	_line_edit = LineEdit.new()
	_line_edit.name = "LineEdit"
	_line_edit.placeholder_text = "Type to chat...  /dm <name> <msg>  /addfriend <name>"
	_line_edit.position = Vector2(6, 4)
	_line_edit.size = Vector2(468, 28)
	_line_edit.add_theme_font_size_override("font_size", 13)
	_line_edit.add_theme_color_override("font_color", Color(1, 1, 1))
	bg.add_child(_line_edit)

	_line_edit.text_submitted.connect(_on_text_submitted)
	_line_edit.gui_input.connect(_on_line_edit_input)

func activate() -> void:
	show()
	_line_edit.clear()
	_line_edit.grab_focus()

func deactivate() -> void:
	hide()
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
