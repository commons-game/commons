## Workbench — crafting station. Ownerless CRDT-persisted structure tile.
##
## Standing within 2 tiles and pressing E opens the CraftingUI in workbench
## mode (3×3 grid, workbench-required recipes unlocked). Proximity check lives
## in Player._try_open_workbench, keyed on object-layer atlas (1,2).
##
## Mirrors Bedroll.gd in shape: a passive ownerless structure with no internal
## state worth persisting beyond the tile itself.
##
## Placed via Player._place_structure → TileMutationBus.request_place_tile,
## spawned by ChunkManager when its chunk loads.
extends Node2D

## World-tile position. Set by ChunkManager when spawning from CRDT.
var world_tile_pos: Vector2i = Vector2i.ZERO

func _ready() -> void:
	z_index = 1

func _draw() -> void:
	# Wooden bench: dark plank top, lighter end-grain accents, two visible legs.
	var top_color   := Color(0.55, 0.38, 0.18)
	var grain_color := Color(0.40, 0.26, 0.10)
	var leg_color   := Color(0.35, 0.22, 0.08)
	draw_rect(Rect2(-7.0, -5.0, 14.0, 4.0), grain_color)
	draw_rect(Rect2(-6.0, -4.0, 12.0, 2.0), top_color)
	draw_line(Vector2(-6.0, -3.0), Vector2(6.0, -3.0), grain_color, 1.0)
	draw_rect(Rect2(-5.0,  0.0, 2.0, 5.0), leg_color)
	draw_rect(Rect2( 3.0,  0.0, 2.0, 5.0), leg_color)
