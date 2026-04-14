## Lantern — toggleable PointLight2D carried by the player.
##
## Toggle with L key. When on at night the player becomes a visible beacon —
## a deliberate risk/reward tradeoff (visibility vs. stealth).
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
