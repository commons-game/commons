## Bedroll — comfort rest point. Ownerless CRDT-persisted structure tile.
##
## Home spawn is the Tether's job (world/structures/Tether.gd). The Bedroll
## exists as a future hook for "skip-to-dawn" or rested-XP mechanics; today
## activate() just flips the colour as a visual acknowledgement.
##
## Placed via Player._place_structure → TileMutationBus.request_place_tile,
## spawned by ChunkManager when its chunk loads.
extends Node2D

## World-tile position. Set by ChunkManager when spawning from CRDT.
var world_tile_pos: Vector2i = Vector2i.ZERO

## Whether this bedroll has been activated (changed colour to indicate use).
## Instance-local state; not persisted across chunk unload.
var _is_home: bool = false

const ACTIVATE_RANGE_TILES := 1.5

func _ready() -> void:
	z_index = 1

func _draw() -> void:
	var mat_color: Color = Color(0.55, 0.38, 0.18) if not _is_home else Color(0.4, 0.65, 0.35)
	draw_rect(Rect2(-7.0, -4.0, 14.0, 8.0), Color(0.25, 0.15, 0.05))
	draw_rect(Rect2(-6.0, -3.0, 12.0, 6.0), mat_color)
	draw_circle(Vector2(6.0, 0.0), 3.5, Color(0.45, 0.28, 0.10))
	draw_circle(Vector2(6.0, 0.0), 2.5, mat_color)
	draw_line(Vector2(-4.0, -3.0), Vector2(-4.0, 3.0), Color(0.65, 0.48, 0.22), 1.0)
	draw_line(Vector2(0.0,  -3.0), Vector2(0.0,  3.0), Color(0.65, 0.48, 0.22), 1.0)

## Called by Player when they step on or use near this bedroll.
## Visual-only today; Tether sets the home spawn anchor.
func activate(_player_world_pos: Vector2) -> void:
	if _is_home:
		return
	_is_home = true
	queue_redraw()
	print("Bedroll activated (rest point only — place a Tether to set home spawn).")
