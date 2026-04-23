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

## Size of the visible daytime-bulb sprite in pixels. Radial gradient gives
## a soft edge so it doesn't look like a flat overlay.
const BULB_TEXTURE_PX := 48

var is_on: bool = false

var _light: PointLight2D = null
var _bulb_texture: Texture2D = null

func _ready() -> void:
	# Draw the bulb on top of the player so the toggle has obvious feedback
	# even in daylight (where the PointLight2D alone would be invisible).
	z_index = 3
	_bulb_texture = NightDarknessScript._make_radial_texture(BULB_TEXTURE_PX)
	_light = PointLight2D.new()
	_light.name = "LanternLight"
	_light.texture = NightDarknessScript._make_radial_texture(128)
	_light.texture_scale = 2.0
	_light.color = Color(0.95, 0.82, 0.55)  # warm lantern glow
	_light.shadow_enabled = false
	add_child(_light)
	_apply_state()

## Visible bulb — drawn only when lit. Uses the shared radial-gradient
## texture so the glow has a soft edge (not a hard-edged overlay).
func _draw() -> void:
	if not is_on or _bulb_texture == null:
		return
	var sz := Vector2(BULB_TEXTURE_PX, BULB_TEXTURE_PX)
	# Modulate alpha at draw time — the texture is full-white with quadratic
	# alpha falloff, so this tints it warm yellow without compounding the alpha.
	draw_texture_rect(_bulb_texture, Rect2(-sz * 0.5, sz), false,
		Color(1.0, 0.85, 0.35, 0.85))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			toggle()

## Toggle the lantern on/off.
func toggle() -> void:
	is_on = not is_on
	print("[LANTERN] toggle → is_on=%s z=%d pos=%s" % [is_on, z_index, position])
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
	queue_redraw()   # refresh the visible bulb
