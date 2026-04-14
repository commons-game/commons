## DayNightSystem — drives CanvasModulate tint from DayClock and pushes
## day/night transitions into VibeBus.
##
## Wiring (set before add_child or in World._setup_day_night_system):
##   canvas_modulate: CanvasModulate  — the node that tints the world
##   vibe_bus: VibeBus                — optional; receives tension/tone pushes
##
## Color gradient (no gray):
##   dawn  → warm pink/orange → white (midday) → warm yellow/orange (afternoon)
##   dusk  → deep orange-red → purple → deep blue-purple (midnight) → back to dawn
##
## sky_color_for_phase() is a static pure function — fully testable without a scene tree.
extends Node

## Gradient stops: [phase_0_to_1, Color].
## Must be sorted by phase and end with phase=1.0 matching phase=0.0.
const _GRADIENT: Array = [
	[0.00, Color(0.85, 0.52, 0.30)],  # dawn: warm pink-orange
	[0.12, Color(1.00, 0.92, 0.78)],  # early morning: soft warm white
	[0.20, Color(1.00, 1.00, 1.00)],  # morning: full white
	[0.30, Color(1.00, 1.00, 1.00)],  # midday peak: full white
	[0.40, Color(1.00, 0.95, 0.75)],  # afternoon: warm yellow
	[0.48, Color(1.00, 0.72, 0.30)],  # late afternoon: golden
	[0.50, Color(0.95, 0.45, 0.12)],  # dusk: deep orange
	[0.56, Color(0.55, 0.20, 0.30)],  # after dusk: dusky red-purple
	[0.63, Color(0.18, 0.08, 0.28)],  # early night: dark purple
	[0.75, Color(0.04, 0.03, 0.12)],  # midnight: deep blue-black
	[0.87, Color(0.06, 0.05, 0.18)],  # late night: blue-black
	[0.93, Color(0.22, 0.10, 0.28)],  # pre-dawn: dark purple
	[1.00, Color(0.85, 0.52, 0.30)],  # dawn again (matches 0.00)
]

## CanvasModulate node to drive. Assigned by World after add_child.
var canvas_modulate: CanvasModulate = null
## VibeBus to push phase transitions into. Optional.
var vibe_bus: Object = null

func _ready() -> void:
	DayClock.phase_changed.connect(_on_phase_changed)

func _process(_delta: float) -> void:
	if canvas_modulate == null:
		return
	canvas_modulate.color = sky_color_for_phase(DayClock.phase_fraction())

## Returns the sky CanvasModulate color for a given phase fraction [0, 1).
## Static so tests can call DayNightSystemScript.sky_color_for_phase(phase)
## without needing a scene tree instance.
static func sky_color_for_phase(phase: float) -> Color:
	var p := fmod(phase, 1.0)
	if p < 0.0:
		p += 1.0
	for i in range(_GRADIENT.size() - 1):
		var t0: float = float(_GRADIENT[i][0])
		var t1: float = float(_GRADIENT[i + 1][0])
		if p >= t0 and p <= t1:
			var span := t1 - t0
			if span <= 0.0:
				return _GRADIENT[i][1] as Color
			var t := (p - t0) / span
			return (_GRADIENT[i][1] as Color).lerp(_GRADIENT[i + 1][1] as Color, t)
	return Color.WHITE

func _on_phase_changed(is_day: bool) -> void:
	if vibe_bus == null:
		return
	if is_day:
		vibe_bus.push("day_night_cycle", 0.0, 0.3, 120.0)
	else:
		vibe_bus.push("day_night_cycle", 0.2, 0.0, 120.0)
