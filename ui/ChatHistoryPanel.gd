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
	const px: int = MARGIN
	const py: int = 720 - PANEL_HEIGHT - MARGIN - 52  # sits above input bar

	# Border
	var border := ColorRect.new()
	border.name = "HistoryBorder"
	border.color = Color(0.3, 0.3, 0.55, 0.9)
	border.position = Vector2(px - 2, py - 2)
	border.size = Vector2(PANEL_WIDTH + 4, PANEL_HEIGHT + 4)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	# Background
	var bg := ColorRect.new()
	bg.name = "HistoryBG"
	bg.color = Color(0.05, 0.05, 0.12, 0.88)
	bg.position = Vector2(px, py)
	bg.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.position = Vector2(px + 4, py + 4)
	_scroll.size = Vector2(PANEL_WIDTH - 8, PANEL_HEIGHT - 8)
	add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.name = "Messages"
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

## Called by Player._unhandled_input — more reliable than CanvasLayer input routing.
func toggle() -> void:
	if visible:
		hide()
	else:
		show()
