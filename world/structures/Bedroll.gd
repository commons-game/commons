## Bedroll — placeable structure that sets the player's home spawn point.
##
## Placed by Player when bedroll is the active hotbar item via the place_use action.
## When the player walks onto (or uses near) the bedroll, emit home_set(world_pos).
## World.gd or Player.gd listens and stores the home position for respawn.
##
## Draws as a simple rolled mat — a rectangle in earthy brown tones.
extends Node2D

## Emitted when the player activates the bedroll. world_pos is in pixels.
signal home_set(world_pos: Vector2)

## World-tile position. Set by Player after instantiating.
var world_tile_pos: Vector2i = Vector2i.ZERO

## Whether this bedroll has been activated (changed color to indicate home).
var _is_home: bool = false

const ACTIVATE_RANGE_TILES := 1.5

func _ready() -> void:
	z_index = 1

func _draw() -> void:
	# Mat body — earthy brown rectangle
	var mat_color: Color = Color(0.55, 0.38, 0.18) if not _is_home else Color(0.4, 0.65, 0.35)
	draw_rect(Rect2(-7.0, -4.0, 14.0, 8.0), Color(0.25, 0.15, 0.05))  # dark outline
	draw_rect(Rect2(-6.0, -3.0, 12.0, 6.0), mat_color)
	# Roll detail at one end
	draw_circle(Vector2(6.0, 0.0), 3.5, Color(0.45, 0.28, 0.10))
	draw_circle(Vector2(6.0, 0.0), 2.5, mat_color)
	# Stripe decoration
	draw_line(Vector2(-4.0, -3.0), Vector2(-4.0, 3.0), Color(0.65, 0.48, 0.22), 1.0)
	draw_line(Vector2(0.0,  -3.0), Vector2(0.0,  3.0), Color(0.65, 0.48, 0.22), 1.0)

## Called by Player when they step on or use near this bedroll.
func activate(player_world_pos: Vector2) -> void:
	if _is_home:
		return
	_is_home = true
	queue_redraw()
	emit_signal("home_set", position)
	print("Home set.")
