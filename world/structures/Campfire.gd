## Campfire — placeable structure that emits light, repels Sprouts.
##
## Placed by Player when campfire is active hotbar item via the place_use action.
## Draws as an animated orange/yellow flickering circle.
## Registers itself with CampfireRegistry on placement; unregisters on free.
##
## LIGHT_RADIUS is in tiles. NightSpawner and Sprout use this for proximity checks.
extends Node2D

const NightDarknessScript := preload("res://world/NightDarkness.gd")

const LIGHT_RADIUS := 6  # tiles

## The world-tile position this campfire occupies. Set by Player after instantiating.
var world_tile_pos: Vector2i = Vector2i.ZERO

## Visual animation state.
var _anim_time: float = 0.0
var _light: PointLight2D = null

func _ready() -> void:
	z_index = 2
	CampfireRegistry.register_campfire(world_tile_pos)
	_attach_light()

func _attach_light() -> void:
	_light = PointLight2D.new()
	# Warm orange campfire glow, covers ~6-tile radius.
	_light.texture       = NightDarknessScript._make_radial_texture(128)
	_light.texture_scale = 1.5
	_light.energy        = 1.2
	_light.color         = Color(1.0, 0.65, 0.25)
	_light.shadow_enabled = false
	add_child(_light)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		CampfireRegistry.unregister_campfire(world_tile_pos)

func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()
	if _light != null:
		_light.energy = 1.1 + sin(_anim_time * 6.0) * 0.12 + sin(_anim_time * 11.3) * 0.06

func _draw() -> void:
	# Flicker: oscillate radius and alpha slightly.
	var flicker: float = sin(_anim_time * 6.0) * 0.12 + sin(_anim_time * 11.3) * 0.06
	var radius: float = 8.0 + flicker * 4.0
	var alpha: float = 0.85 + flicker * 0.15

	# Outer glow (dark orange, large)
	draw_circle(Vector2.ZERO, radius + 4.0, Color(0.6, 0.2, 0.0, alpha * 0.4))
	# Main flame body (bright orange)
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.55 + flicker * 0.1, 0.05, alpha))
	# Inner hot core (yellow-white)
	draw_circle(Vector2.ZERO, radius * 0.45, Color(1.0, 0.95, 0.5, alpha))
	# Ember sparks: small dots offset from center
	for i in range(3):
		var angle: float = _anim_time * 2.0 + i * 2.094  # 2π/3 apart
		var spark_r: float = radius * 0.6 + sin(_anim_time * 4.0 + i) * 2.0
		var spark_pos := Vector2(cos(angle) * spark_r * 0.3, sin(angle) * spark_r * 0.3)
		draw_circle(spark_pos, 1.5, Color(1.0, 0.85, 0.1, alpha * 0.9))
