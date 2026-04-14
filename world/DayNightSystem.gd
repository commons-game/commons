## DayNightSystem — drives CanvasModulate tint from DayClock and pushes
## day/night transitions into VibeBus.
##
## Wiring (set before add_child or in _ready via $-paths):
##   canvas_modulate: CanvasModulate  — the node that tints the world
##   vibe_bus: VibeBus                — optional; receives tension/tone pushes
##
## Day color  : white (1, 1, 1)
## Night color: dark blue-purple (0.08, 0.06, 0.18)
## Transition is driven by DayClock.sky_alpha() each frame — smooth sinusoidal.
extends Node

## Tint colors for the two phases.
const DAY_COLOR   := Color(1.00, 1.00, 1.00)        # full bright
const NIGHT_COLOR := Color(0.08, 0.06, 0.18)        # deep night

## CanvasModulate node to drive. Assigned by World after add_child.
var canvas_modulate: CanvasModulate = null
## VibeBus to push phase transitions into. Optional.
var vibe_bus: Object = null

func _ready() -> void:
	DayClock.phase_changed.connect(_on_phase_changed)

func _process(_delta: float) -> void:
	if canvas_modulate == null:
		return
	var alpha := DayClock.sky_alpha()
	canvas_modulate.color = DAY_COLOR.lerp(NIGHT_COLOR, alpha)

func _on_phase_changed(is_day: bool) -> void:
	if vibe_bus == null:
		return
	if is_day:
		# Dawn: tension eases, tone warms
		vibe_bus.push("day_night_cycle", 0.0, 0.3, 120.0)
	else:
		# Dusk: tension rises slightly, tone cools
		vibe_bus.push("day_night_cycle", 0.2, 0.0, 120.0)
