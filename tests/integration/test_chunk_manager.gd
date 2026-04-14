## Integration tests for ChunkManager.
## Tests load/unload radius and tile placement at negative coordinates.
## Note: these tests require a scene tree with ChunkManager instantiated.
extends GdUnitTestSuite

var _chunk_manager: ChunkManager

func before_test() -> void:
	## Instantiate a fresh ChunkManager for each test.
	_chunk_manager = ChunkManager.new()
	add_child(_chunk_manager)

func after_test() -> void:
	if is_instance_valid(_chunk_manager):
		_chunk_manager.queue_free()
	_chunk_manager = null

# --- Load radius ---

func test_chunks_loaded_in_radius_after_player_move() -> void:
	## After update_player_position, all chunks within LOAD_RADIUS must be loaded.
	_chunk_manager.update_player_position(Vector2i(0, 0))
	await get_tree().process_frame
	var loaded := _chunk_manager.get_loaded_chunk_coords()
	var radius := Constants.LOAD_RADIUS
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var coords := Vector2i(dx, dy)
			assert_that(loaded.has(coords)).is_true()

func test_chunks_unloaded_when_player_moves_far() -> void:
	## After moving player far, original chunks should be unloaded.
	_chunk_manager.update_player_position(Vector2i(0, 0))
	await get_tree().process_frame
	## Confirm chunk (0,0) is loaded
	assert_that(_chunk_manager.get_chunk(Vector2i(0, 0)) != null).is_true()
	## Move player beyond UNLOAD_RADIUS
	var far := Constants.UNLOAD_RADIUS + 2
	_chunk_manager.update_player_position(Vector2i(far * Constants.CHUNK_SIZE, 0))
	await get_tree().process_frame
	## Original chunk (0,0) should now be unloaded
	assert_that(_chunk_manager.get_chunk(Vector2i(0, 0))).is_null()

# --- Negative coordinate tile placement ---

func test_place_tile_at_negative_world_coords() -> void:
	## place_tile at (-1,-1) should hit chunk (-1,-1), local (15,15).
	_chunk_manager.update_player_position(Vector2i(-8, -8))  # load negative chunks
	await get_tree().process_frame
	## Ensure chunk (-1,-1) is loaded
	assert_that(_chunk_manager.get_chunk(Vector2i(-1, -1)) != null).is_true()
	## Place tile at world (-1,-1)
	_chunk_manager.place_tile(Vector2i(-1, -1), 1, 0, Vector2i(0, 0), 0, "test-player")
	## Verify tile appears in CRDT
	var chunk := _chunk_manager.get_chunk(Vector2i(-1, -1))
	var tile := chunk.crdt.get_tile(1, Vector2i(15, 15))
	assert_that(tile.is_empty()).is_false()
	assert_that(tile["tile_id"]).is_equal(0)

func test_place_tile_at_negative_chunk_boundary() -> void:
	## Tile (-16,-16) is local (0,0) in chunk (-1,-1).
	_chunk_manager.update_player_position(Vector2i(-8, -8))
	await get_tree().process_frame
	_chunk_manager.place_tile(Vector2i(-16, -16), 1, 0, Vector2i(1, 0), 0, "test-player")
	var chunk := _chunk_manager.get_chunk(Vector2i(-1, -1))
	var tile := chunk.crdt.get_tile(1, Vector2i(0, 0))
	assert_that(tile.is_empty()).is_false()
	assert_that(tile["tile_id"]).is_equal(0)

func test_remove_tile_at_negative_world_coords() -> void:
	## remove_tile at negative coords should write tombstone.
	_chunk_manager.update_player_position(Vector2i(-8, -8))
	await get_tree().process_frame
	## First place, then remove
	_chunk_manager.place_tile(Vector2i(-5, -3), 1, 0, Vector2i(0, 0), 0, "test-player")
	_chunk_manager.remove_tile(Vector2i(-5, -3), 1, "test-player")
	## Compute expected chunk and local
	var expected_chunk := CoordUtils.world_to_chunk(Vector2i(-5, -3))
	var expected_local := CoordUtils.world_to_local(Vector2i(-5, -3))
	var chunk := _chunk_manager.get_chunk(expected_chunk)
	assert_that(chunk != null).is_true()
	var tile := chunk.crdt.get_tile(1, expected_local)
	assert_that(tile.is_empty()).is_false()
	assert_that(tile["tile_id"]).is_equal(-1)  # tombstone

func test_place_tile_at_chunk_boundary() -> void:
	## Tile (15, 0) is local (15,0) in chunk (0,0).
	## Tile (16, 0) is local (0, 0) in chunk (1,0).
	_chunk_manager.update_player_position(Vector2i(8, 8))
	await get_tree().process_frame
	_chunk_manager.place_tile(Vector2i(15, 0), 1, 0, Vector2i(0, 0), 0, "test-player")
	_chunk_manager.place_tile(Vector2i(16, 0), 1, 0, Vector2i(1, 0), 0, "test-player")
	var chunk0 := _chunk_manager.get_chunk(Vector2i(0, 0))
	var chunk1 := _chunk_manager.get_chunk(Vector2i(1, 0))
	assert_that(chunk0.crdt.get_tile(1, Vector2i(15, 0)).is_empty()).is_false()
	assert_that(chunk1.crdt.get_tile(1, Vector2i(0, 0)).is_empty()).is_false()
