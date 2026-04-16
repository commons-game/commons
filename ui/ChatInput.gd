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
	# Outer border rect for visibility
	var border := ColorRect.new()
	border.name = "InputBorder"
	border.color = Color(0.4, 0.6, 1.0, 0.9)
	border.position = Vector2((1280 - 484) / 2, 720 - 54)
	border.size = Vector2(484, 44)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.focus_mode   = Control.FOCUS_NONE
	add_child(border)

	var bg := ColorRect.new()
	bg.name = "InputBG"
	bg.color = Color(0.08, 0.08, 0.16, 0.96)
	bg.position = Vector2((1280 - 480) / 2, 720 - 52)
	bg.size = Vector2(480, 40)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.focus_mode   = Control.FOCUS_NONE
	add_child(bg)

	_line_edit = LineEdit.new()
	_line_edit.name = "LineEdit"
	_line_edit.placeholder_text = "Say something...  /dm <name> <msg>  /addfriend <name>"
	_line_edit.position = Vector2(6, 6)
	_line_edit.size = Vector2(468, 28)
	_line_edit.add_theme_font_size_override("font_size", 13)
	_line_edit.add_theme_color_override("font_color", Color(1, 1, 1))
	_line_edit.add_theme_color_override("font_placeholder_color", Color(0.6, 0.7, 0.9, 0.7))
	# Solid background so text is always readable regardless of game theme
	var le_style := StyleBoxFlat.new()
	le_style.bg_color = Color(0.12, 0.12, 0.22, 1.0)
	_line_edit.add_theme_stylebox_override("normal", le_style)
	_line_edit.add_theme_stylebox_override("focus",  le_style)
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
	if trimmed.begins_with("/"):
		_handle_slash(trimmed)
		deactivate()
		get_viewport().set_input_as_handled()
		return
	if not trimmed.is_empty():
		var player_id:   String = PlayerIdentity.id
		var player_name: String = PlayerIdentity.display_name
		ChatSystem.handle_input(trimmed, player_id, player_name)
	deactivate()
	get_viewport().set_input_as_handled()

func _handle_slash(cmd: String) -> void:
	match cmd:
		"/telemetry on":
			ErrorReporter.set_consent(true)
			_show_system("Telemetry enabled. Thank you for helping!")
		"/telemetry off":
			ErrorReporter.set_consent(false)
			_show_system("Telemetry disabled. Pending reports cleared.")
		"/telemetry reset":
			ErrorReporter.consent_asked = false
			ErrorReporter._save_consent()
			_show_system("Telemetry consent reset — you'll be asked again next launch.")
		_:
			if cmd == "/telemetry" or cmd == "/telemetry status":
				var s := "on" if ErrorReporter.opted_in else "off"
				_show_system("Telemetry is %s.  /telemetry on | off | reset" % s)
			else:
				_show_system("Unknown command: %s" % cmd)

func _show_system(msg: String) -> void:
	print("[System] %s" % msg)
	ChatSystem.handle_input("[System] " + msg, "system", "System")

func _on_line_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			deactivate()
			get_viewport().set_input_as_handled()
