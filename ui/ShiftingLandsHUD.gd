## ShiftingLandsHUD — pulsing border overlay when the world is split.
## Invisible when players are merged. Layer 18 (below debug overlay at 20).
## Add as child of World via _setup_shifting_lands_hud().
extends CanvasLayer

const BORDER_WIDTH := 6
const PULSE_SPEED  := 1.5

var _top: ColorRect    = null
var _bottom: ColorRect = null
var _left: ColorRect   = null
var _right: ColorRect  = null
var _time: float = 0.0
var _active: bool = false

func _init() -> void:
	layer = 18

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	var color := Color(0.7, 0.2, 1.0, 0.8)
	_top    = _make_rect(Vector2(0, 0),                   Vector2(1280, BORDER_WIDTH), color)
	_bottom = _make_rect(Vector2(0, 720 - BORDER_WIDTH),  Vector2(1280, BORDER_WIDTH), color)
	_left   = _make_rect(Vector2(0, 0),                   Vector2(BORDER_WIDTH, 720),  color)
	_right  = _make_rect(Vector2(1280 - BORDER_WIDTH, 0), Vector2(BORDER_WIDTH, 720),  color)

func _make_rect(pos: Vector2, sz: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	var alpha := 0.4 + 0.4 * sin(_time * PULSE_SPEED * TAU)
	var color := Color(0.7, 0.2, 1.0, alpha)
	_top.color    = color
	_bottom.color = color
	_left.color   = color
	_right.color  = color

func activate() -> void:
	_active = true
	_time = 0.0
	show()

func deactivate() -> void:
	_active = false
	hide()
