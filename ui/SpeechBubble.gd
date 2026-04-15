## SpeechBubble — floats above a character, fades over 4 seconds, then frees itself.
##
## Usage:
##   var bubble := SpeechBubbleScript.new()
##   bubble.setup(text, sender_name, is_dm)
##   character_node.add_child(bubble)
##   bubble.position = Vector2(0, -32 - existing_bubble_height_offset)
extends Node2D

const FADE_DURATION := 4.0
const MAX_WIDTH     := 180.0
const PADDING_X     := 6.0
const PADDING_Y     := 4.0
const FONT_SIZE     := 12

## Background colors for normal vs DM bubbles.
const COLOR_NORMAL := Color(0.15, 0.15, 0.15, 0.85)
const COLOR_DM     := Color(0.1,  0.2,  0.45, 0.90)
const COLOR_TEXT   := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_NAME   := Color(0.8, 0.85, 1.0, 1.0)

var _text: String = ""
var _sender_name: String = ""
var _is_dm: bool = false
var _fade_timer: float = 0.0

## Cached layout measurements (computed once in setup)
var _lines: Array = []  # Array of String
var _bubble_size: Vector2 = Vector2.ZERO

## Height of this bubble (set after setup; used by Player for stacking).
var bubble_height: float = 0.0

func setup(text: String, sender_name: String, is_dm: bool = false) -> void:
	_text = text
	_sender_name = sender_name
	_is_dm = is_dm
	_fade_timer = 0.0
	_compute_layout()
	queue_redraw()

func _compute_layout() -> void:
	# Wrap text naively by character count (no font metrics in headless/GDScript).
	# ~22 chars per line at font_size 12 with ~180px max width.
	var chars_per_line := int(MAX_WIDTH / (FONT_SIZE * 0.6))
	_lines = _wrap_text(_text, chars_per_line)
	var line_height := float(FONT_SIZE) + 2.0
	var content_h := float(_lines.size()) * line_height
	if not _sender_name.is_empty():
		content_h += line_height  # name row
	_bubble_size = Vector2(MAX_WIDTH + PADDING_X * 2.0, content_h + PADDING_Y * 2.0)
	bubble_height = _bubble_size.y

func _wrap_text(text: String, max_chars: int) -> Array:
	var words := text.split(" ")
	var result: Array = []
	var current_line := ""
	for word in words:
		if current_line.is_empty():
			current_line = word
		elif (current_line + " " + word).length() <= max_chars:
			current_line += " " + word
		else:
			result.append(current_line)
			current_line = word
	if not current_line.is_empty():
		result.append(current_line)
	return result

func _process(delta: float) -> void:
	_fade_timer += delta
	var alpha := 1.0 - clampf(_fade_timer / FADE_DURATION, 0.0, 1.0)
	modulate.a = alpha
	if alpha <= 0.0:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	if _bubble_size == Vector2.ZERO:
		return
	var bg_color: Color = COLOR_DM if _is_dm else COLOR_NORMAL
	# Draw background centered horizontally above origin
	var rect_pos := Vector2(-_bubble_size.x * 0.5, -_bubble_size.y)
	draw_rect(Rect2(rect_pos, _bubble_size), bg_color)

	var line_height := float(FONT_SIZE) + 2.0
	var y := rect_pos.y + PADDING_Y

	# Draw sender name in a slightly lighter color if present
	if not _sender_name.is_empty():
		draw_string(ThemeDB.fallback_font,
			Vector2(rect_pos.x + PADDING_X, y + float(FONT_SIZE)),
			_sender_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_NAME)
		y += line_height

	# Draw text lines
	for line in _lines:
		draw_string(ThemeDB.fallback_font,
			Vector2(rect_pos.x + PADDING_X, y + float(FONT_SIZE)),
			line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_TEXT)
		y += line_height
