## TileInteraction — mouse click handler for tile placement/removal.
## Left click  = place "default" tile on layer 1 via TileMutationBus (syncs to peers).
## Right click = remove tile from layer 1 via TileMutationBus (syncs to peers).
## Mouse position is converted from viewport to world tile coordinates.
extends Node

@onready var _bus := $"../../TileMutationBus"

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	# Convert from screen coords to world pixel coords
	var world_px := get_viewport().get_canvas_transform().affine_inverse() \
	                * get_viewport().get_mouse_position()
	# Convert world pixels to world tile coordinates using floor division
	var tile_pos := Vector2i(int(floorf(world_px.x / Constants.TILE_SIZE)),
	                         int(floorf(world_px.y / Constants.TILE_SIZE)))
	if event.button_index == MOUSE_BUTTON_LEFT:
		_bus.request_place_tile(tile_pos, 1, "default")
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_bus.request_remove_tile(tile_pos, 1)
