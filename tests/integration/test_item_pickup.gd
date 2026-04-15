## Integration tests for ground loot tile (atlas 3,1) pickup mechanic.
##
## Covers:
##   1. Loot tile placed at (3,1) on the object layer is detectable via has_tile_at
##   2. Removing the loot tile leaves no tile (simulates pickup)
##   3. Atlas (3,1) is registered in Chunk.ATLAS_TILES and has no collision polygon
extends GdUnitTestSuite

var _cm: ChunkManager

func before_test() -> void:
	_cm = ChunkManager.new()
	add_child(_cm)
	_cm.update_player_position(Vector2i(0, 0))
	await get_tree().process_frame

func after_test() -> void:
	if is_instance_valid(_cm):
		_cm.queue_free()
	_cm = null

# ---------------------------------------------------------------------------
# Test 1: loot tile placed on object layer is detectable
# ---------------------------------------------------------------------------

func test_loot_tile_placed_and_detected() -> void:
	var pos := Vector2i(4, 4)
	# Clear any existing object tile first
	_cm.remove_tile(pos, 1, "setup")
	# Place loot tile at atlas (3,1) on object layer
	_cm.place_tile(pos, 1, 0, Vector2i(3, 1), 0, "test")
	assert_bool(_cm.has_tile_at(pos, 1)).is_true()
	# Verify CRDT record stores the correct atlas coords
	var chunk := _cm.get_chunk(CoordUtils.world_to_chunk(pos))
	var local := CoordUtils.world_to_local(pos)
	var tile: Dictionary = chunk.crdt.get_tile(1, local)
	assert_int(tile.get("atlas_x", -1)).is_equal(3)
	assert_int(tile.get("atlas_y", -1)).is_equal(1)

# ---------------------------------------------------------------------------
# Test 2: removing loot tile (pickup) leaves no tile
# ---------------------------------------------------------------------------

func test_pickup_removes_tile() -> void:
	var pos := Vector2i(5, 5)
	_cm.remove_tile(pos, 1, "setup")
	_cm.place_tile(pos, 1, 0, Vector2i(3, 1), 0, "test")
	assert_bool(_cm.has_tile_at(pos, 1)).is_true()
	# Simulate pickup: remove the tile
	_cm.remove_tile(pos, 1, "pickup")
	assert_bool(_cm.has_tile_at(pos, 1)).is_false()

# ---------------------------------------------------------------------------
# Test 3: loot tile (3,1) is in ATLAS_TILES and has no collision polygon
# ---------------------------------------------------------------------------

func test_loot_tile_has_no_collision() -> void:
	# Verify atlas (3,1) is registered in Chunk.ATLAS_TILES
	const ChunkScript := preload("res://world/chunk/Chunk.gd")
	assert_bool(ChunkScript.ATLAS_TILES.has(Vector2i(3, 1))).is_true()

	# Load a chunk and verify the tile source has (3,1) registered
	var chunk := _cm.get_chunk(Vector2i(0, 0))
	assert_object(chunk).is_not_null()

	# The loot tile should have zero collision polygons (player walks over it)
	var source := chunk.object_layer.tile_set.get_source(0) as TileSetAtlasSource
	assert_object(source).is_not_null()
	assert_bool(source.has_tile(Vector2i(3, 1))).is_true()
	var td := source.get_tile_data(Vector2i(3, 1), 0)
	assert_object(td).is_not_null()
	# Collision polygon count should be 0 (no collision for loot)
	assert_int(td.get_collision_polygons_count(0)).is_equal(0)
