## PerformanceHUD — toggleable FPS / frame-time overlay (F3).
##
## Structure:
##   PerformanceHUD (CanvasLayer, layer 15)
##     ├── _label: Label          — FPS + ms text, top-left
##     └── _graph_control: Control — rolling bar chart drawn via _draw()
##
## Default: hidden. Press F3 to toggle.
extends CanvasLayer

const GRAPH_W   := 240
const GRAPH_H   := 60
const MAX_FRAMES := 120
const LABEL_X   := 10
const LABEL_Y   := 10
const GRAPH_Y   := 28   # below label

var _label: Label = null
var _graph_control: Control = null
var _frame_times: Array[float] = []

# ---------------------------------------------------------------------------
# Inner Control that draws the bar chart.
# ---------------------------------------------------------------------------
class GraphControl extends Control:
	func _draw() -> void:
		var parent: Node = get_parent()
		if parent == null:
			return
		var times: Array[float] = parent._frame_times

		# Background
		draw_rect(Rect2(0, 0, 240, 60), Color(0.1, 0.1, 0.1, 0.7))

		# Reference lines (drawn behind bars)
		# 33 ms line
		var y_33: float = 60.0 - clampf(33.0 / 50.0, 0.0, 1.0) * 60.0
		draw_line(Vector2(0, y_33), Vector2(240, y_33), Color(1, 0, 0, 0.5), 1.0)
		# 16.7 ms line
		var y_167: float = 60.0 - clampf(16.7 / 50.0, 0.0, 1.0) * 60.0
		draw_line(Vector2(0, y_167), Vector2(240, y_167), Color(0, 1, 0, 0.3), 1.0)

		# Bars
		var bar_w: float = 240.0 / 120.0  # = 2 px
		var count: int = times.size()
		for i in range(count):
			var ms: float = times[i]
			var bar_h: float = clampf(ms / 50.0, 0.0, 1.0) * 60.0
			var col: Color
			if ms < 16.7:
				col = Color(0.2, 0.9, 0.2)   # green
			elif ms < 33.0:
				col = Color(0.95, 0.85, 0.1) # yellow
			else:
				col = Color(0.9, 0.15, 0.15) # red
			var x: float = i * bar_w
			draw_rect(Rect2(x, 60.0 - bar_h, bar_w, bar_h), col)

# ---------------------------------------------------------------------------
# PerformanceHUD lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	layer = 15
	visible = false

	_label = Label.new()
	_label.name = "PerfLabel"
	_label.position = Vector2(LABEL_X, LABEL_Y)
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.text = "FPS: --  |  --ms"
	add_child(_label)

	_graph_control = GraphControl.new()
	_graph_control.name = "PerfGraph"
	_graph_control.position = Vector2(LABEL_X, GRAPH_Y)
	_graph_control.custom_minimum_size = Vector2(GRAPH_W, GRAPH_H)
	_graph_control.size = Vector2(GRAPH_W, GRAPH_H)
	add_child(_graph_control)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			visible = not visible

func _process(delta: float) -> void:
	var ms: float = delta * 1000.0
	_frame_times.append(ms)
	if _frame_times.size() > MAX_FRAMES:
		_frame_times.pop_front()

	if ms > 33.0:
		print("[PERF SPIKE] %.1fms (frame %d)" % [ms, Engine.get_process_frames()])

	if visible:
		var fps: int = int(Engine.get_frames_per_second())
		_label.text = "FPS: %d  |  %.1fms" % [fps, ms]
		_label.add_theme_color_override("font_color",
			Color(1, 0.2, 0.2) if ms > 33.0 else Color.WHITE)
		_graph_control.queue_redraw()
