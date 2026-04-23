## Lantern — toggleable PointLight2D carried by the player.
##
## SINGLE source of truth for the player's local lantern glow. When on it
## emits an 8-tile radius warm glow; when off the player has no local light
## (only CanvasModulate dims the world via NightDarkness).
##
## Toggle via:
##   - right-click while the lantern is the active tool (TileInteraction)
##   - the L key anywhere (Player._unhandled_input)
##
## Auto-off: Player._auto_off_lantern_if_dropped() forces is_on=false each
## frame if the lantern isn't held in a tool_slot, so dragging it to the bag
## or dropping it on death extinguishes it.
##
## Attach as a child of Player.
extends Node2D

## Visible lantern radius in tiles. 16 px/tile × 8 tiles = 128 px radius.
## The texture is 128 px and drawn at scale 2.0 → 256 px diameter = 8-tile radius.
const LANTERN_TILE_RADIUS := 8

const NightDarknessScript := preload("res://world/NightDarkness.gd")

var is_on: bool = false

var _light: PointLight2D = null

func _ready() -> void:
	_light = PointLight2D.new()
	_light.name = "LanternLight"
	_light.texture = NightDarknessScript._make_radial_texture(128)
	_light.texture_scale = 2.0
	_light.color = Color(0.95, 0.82, 0.55)  # warm lantern glow
	_light.shadow_enabled = false
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
	_light.energy  = 0.85 if is_on else 0.0
