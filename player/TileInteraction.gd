## TileInteraction — mouse-driven tile interaction, tool-aware.
##
## Active tool (from Player.inventory.get_active_tool()) determines behavior:
##
##   shovel — digging tool
##     Left click  : dig tile at layer 0 (ground). Removes it, adds 1 "dirt" to bag.
##     Right click : if bag has "dirt", place "dirt" tile at layer 0, consume 1.
##
##   (no tool / other tool — legacy fallback)
##     Left click  : place "default" tile on layer 1
##     Right click : remove tile from layer 1
##
## DIG_RANGE_TILES: max distance in tiles from player centre to target tile.
extends Node

const DIG_RANGE_TILES := 5

@onready var _bus         := $"../../TileMutationBus"
@onready var _chunk_mgr   := $"../../ChunkManager"

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	var world_px := get_viewport().get_canvas_transform().affine_inverse() \
	                * get_viewport().get_mouse_position()
	var tile_pos := Vector2i(int(floorf(world_px.x / Constants.TILE_SIZE)),
	                         int(floorf(world_px.y / Constants.TILE_SIZE)))

	var player := get_parent()
	var inventory: Object = player.get("inventory")

	if inventory != null:
		var active_tool: Dictionary = inventory.get_active_tool()
		var tool_id: String = str(active_tool.get("id", ""))
		if tool_id == "shovel":
			_handle_shovel(event.button_index, tile_pos, player, inventory)
			return

	# Legacy fallback (no tool or non-shovel tool)
	if event.button_index == MOUSE_BUTTON_LEFT:
		_bus.request_place_tile(tile_pos, 1, "default")
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_bus.request_remove_tile(tile_pos, 1)

# ---------------------------------------------------------------------------
# Shovel
# ---------------------------------------------------------------------------

func _handle_shovel(button: int, tile_pos: Vector2i,
		player: Node, inventory: Object) -> void:
	if not _in_range(tile_pos, player):
		return
	if button == MOUSE_BUTTON_LEFT:
		_shovel_dig(tile_pos, inventory)
	elif button == MOUSE_BUTTON_RIGHT:
		_shovel_place(tile_pos, inventory)

func _shovel_dig(tile_pos: Vector2i, inventory: Object) -> void:
	# Only dig if there is actually a tile here.
	if not _chunk_mgr.has_tile_at(tile_pos, 0):
		return
	_bus.request_remove_tile(tile_pos, 0)
	# Drop 1 dirt into the player's bag.
	inventory.add_to_bag({"id": "dirt", "category": "material", "count": 1}, 32)

func _shovel_place(tile_pos: Vector2i, inventory: Object) -> void:
	# Need at least 1 dirt in bag.
	if inventory.bag_stack_total("dirt") < 1:
		return
	# Only place on empty ground (don't stack tiles).
	if _chunk_mgr.has_tile_at(tile_pos, 0):
		return
	_bus.request_place_tile(tile_pos, 0, "dirt")
	inventory.remove_from_bag("dirt", 1)

# ---------------------------------------------------------------------------
# Range check
# ---------------------------------------------------------------------------

func _in_range(tile_pos: Vector2i, player: Node) -> bool:
	var player_tile := Vector2i(
		int(floorf(player.position.x / Constants.TILE_SIZE)),
		int(floorf(player.position.y / Constants.TILE_SIZE)))
	var dx := abs(tile_pos.x - player_tile.x)
	var dy := abs(tile_pos.y - player_tile.y)
	return dx <= DIG_RANGE_TILES and dy <= DIG_RANGE_TILES
