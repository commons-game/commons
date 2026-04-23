## Lantern — toggleable PointLight2D carried by the player.
##
## Toggle with right-click while the lantern is the active tool, or with the L
## key from anywhere. When on at night the player becomes a visible beacon —
## a deliberate risk/reward tradeoff (visibility vs. stealth).
##
## Auto-off: Player._auto_off_lantern_if_dropped() forces is_on=false each frame
## if the lantern isn't held in a tool_slot, so dragging it to the bag or
## dropping it on death extinguishes it.
##
## Attach as a child of Player. The owning scene must have a PointLight2D named
## "LanternLight" as a child of this node, or this script creates one.
extends Node2D

## Whether the lantern is currently lit.
var is_on: bool = false

var _light: PointLight2D = null

func _ready() -> void:
	# Use an existing LanternLight child if present, otherwise create one.
	_light = get_node_or_null("LanternLight") as PointLight2D
	if _light == null:
		_light = PointLight2D.new()
		_light.name = "LanternLight"
		add_child(_light)
	_apply_state()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			toggle()

## Toggle the lantern on/off.
func toggle() -> void:
	is_on = not is_on
	_apply_state()

## Force the lantern to a specific state.
func set_on(value: bool) -> void:
	is_on = value
	_apply_state()

func _apply_state() -> void:
	if _light == null:
		return
	_light.enabled = is_on
	# Warm yellow-orange glow when lit.
	_light.color = Color(1.0, 0.85, 0.4) if is_on else Color.WHITE
	_light.energy = 1.2 if is_on else 0.0
