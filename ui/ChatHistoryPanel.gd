## ChatHistoryPanel — scrollable chat history, toggled by Tab.
##
## CanvasLayer at layer 19. Invisible by default.
## Add as child of World or via World._setup_chat_system().
##
## Usage:
##   ChatSystem.message_received.connect(func(sn, t, dm, _id): panel.add_message(sn, t, dm))
extends CanvasLayer

const MAX_MESSAGES := 20
const PANEL_WIDTH  := 320
const PANEL_HEIGHT := 160
const MARGIN       := 8

## Normal message color and DM tint.
const COLOR_NORMAL := Color(0.9, 0.9, 0.9)
const COLOR_DM     := Color(0.6, 0.8, 1.0)
const COLOR_SYSTEM := Color(1.0, 0.85, 0.4)

var _vbox: VBoxContainer = null
var _scroll: ScrollContainer = null
var _message_count: int = 0

func _init() -> void:
	layer = 19

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	var panel := Panel.new()
	panel.name = "HistoryBG"
	# Position bottom-left of viewport (1280×720)
	panel.position = Vector2(MARGIN, 720 - PANEL_HEIGHT - MARGIN - 48)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	panel.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.75)
	style.border_width_bottom = 1
	style.border_width_top    = 1
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_color = Color(0.3, 0.3, 0.5, 0.8)
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left   = 4
	_scroll.offset_top    = 4
	_scroll.offset_right  = -4
	_scroll.offset_bottom = -4
	panel.add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.name = "Messages"
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_vbox)

func add_message(sender_name: String, text: String, is_dm: bool) -> void:
	if _vbox == null:
		return
	var label := Label.new()
	var display_text: String
	if sender_name == "[System]":
		display_text = "[System] " + text
		label.add_theme_color_override("font_color", COLOR_SYSTEM)
	elif is_dm:
		display_text = "[DM] %s: %s" % [sender_name, text]
		label.add_theme_color_override("font_color", COLOR_DM)
	else:
		display_text = "%s: %s" % [sender_name, text]
		label.add_theme_color_override("font_color", COLOR_NORMAL)
	label.text = display_text
	label.add_theme_font_size_override("font_size", 11)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(PANEL_WIDTH - 20, 0)
	_vbox.add_child(label)
	_message_count += 1

	# Prune old messages if over limit
	while _message_count > MAX_MESSAGES:
		var oldest := _vbox.get_child(0)
		oldest.queue_free()
		_message_count -= 1

	# Auto-scroll to bottom next frame
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_TAB:
		visible = not visible
		get_viewport().set_input_as_handled()
