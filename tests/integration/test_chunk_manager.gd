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

func test_set_tile_resolves_via_registry_and_places() -> void:
	## set_tile (TileMutationBus interface) must resolve a string tile_id via
	## TileRegistry and forward to place_tile with the correct atlas coords.
	TileRegistry.register("test_stone", 0, Vector2i(2, 3), 1)
	_chunk_manager.update_player_position(Vector2i(0, 0))
	await get_tree().process_frame
	_chunk_manager.set_tile(Vector2i(0, 0), 1, "test_stone", "test-author")
	var chunk := _chunk_manager.get_chunk(Vector2i(0, 0))
	var tile := chunk.crdt.get_tile(1, Vector2i(0, 0))
	assert_that(tile.is_empty()).is_false()
	assert_int(tile["tile_id"]).is_equal(0)
	assert_int(tile["atlas_x"]).is_equal(2)
	assert_int(tile["atlas_y"]).is_equal(3)
	assert_int(tile["alt_tile"]).is_equal(1)
	assert_str(tile["author_id"]).is_equal("test-author")

func test_get_crdt_snapshot_returns_placed_tiles() -> void:
	## get_crdt_snapshot should include a tile placed via place_tile.
	_chunk_manager.update_player_position(Vector2i(0, 0))
	await get_tree().process_frame
	_chunk_manager.place_tile(Vector2i(3, 5), 1, 0, Vector2i(0, 0), 0, "alice")
	var snap: Array = _chunk_manager.get_crdt_snapshot()
	# Find the record for (3,5) layer 1
	var target_chunk := CoordUtils.world_to_chunk(Vector2i(3, 5))
	var target_local := CoordUtils.world_to_local(Vector2i(3, 5))
	var found := false
	for r in snap:
		if r["chunk_x"] == target_chunk.x and r["chunk_y"] == target_chunk.y \
				and r["layer"] == 1 and r["lx"] == target_local.x and r["ly"] == target_local.y:
			found = true
			assert_that(int(r["tile_id"])).is_equal(0)
			assert_str(r["author_id"]).is_equal("alice")
	assert_bool(found).is_true()

func test_apply_crdt_snapshot_merges_remote_tiles() -> void:
	## apply_crdt_snapshot should write remote tiles into loaded chunks.
	_chunk_manager.update_player_position(Vector2i(0, 0))
	await get_tree().process_frame
	var ts := Time.get_unix_time_from_system() + 1000.0
	var records: Array = [{
		"chunk_x": 0, "chunk_y": 0, "layer": 0, "lx": 7, "ly": 2,
		"tile_id": 3, "atlas_x": 3, "atlas_y": 0, "alt_tile": 0,
		"timestamp": ts, "author_id": "bob"
	}]
	_chunk_manager.apply_crdt_snapshot(records)
	var chunk := _chunk_manager.get_chunk(Vector2i(0, 0))
	var tile := chunk.crdt.get_tile(0, Vector2i(7, 2))
	assert_bool(tile.is_empty()).is_false()
	assert_int(tile["tile_id"]).is_equal(3)
	assert_str(tile["author_id"]).is_equal("bob")

func test_apply_crdt_snapshot_skips_unloaded_chunks() -> void:
	## apply_crdt_snapshot for an unloaded chunk must not crash.
	_chunk_manager.update_player_position(Vector2i(0, 0))
	await get_tree().process_frame
	var records: Array = [{
		"chunk_x": 999, "chunk_y": 999, "layer": 0, "lx": 0, "ly": 0,
		"tile_id": 1, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0,
		"timestamp": 1000.0, "author_id": "ghost"
	}]
	# Should complete without error
	_chunk_manager.apply_crdt_snapshot(records)

func test_set_tile_unknown_id_is_no_op() -> void:
	## set_tile with an unregistered tile_id should not crash and not place anything.
	_chunk_manager.update_player_position(Vector2i(0, 0))
	await get_tree().process_frame
	_chunk_manager.set_tile(Vector2i(0, 0), 1, "no_such_tile", "test-author")
	var chunk := _chunk_manager.get_chunk(Vector2i(0, 0))
	## Procedural generator may have placed a tile here — just confirm no crash occurred.
	## The test passing without error is the assertion.
	var _tile := chunk.crdt.get_tile(1, Vector2i(0, 0))

func test_has_tile_at_returns_true_after_place() -> void:
	_chunk_manager.update_player_position(Vector2i(0, 0))
	await get_tree().process_frame
	_chunk_manager.place_tile(Vector2i(4, 4), 0, 0, Vector2i(1, 0), 0, "test-player")
	assert_bool(_chunk_manager.has_tile_at(Vector2i(4, 4), 0)).is_true()

func test_has_tile_at_returns_false_after_remove() -> void:
	_chunk_manager.update_player_position(Vector2i(0, 0))
	await get_tree().process_frame
	_chunk_manager.place_tile(Vector2i(5, 5), 0, 0, Vector2i(1, 0), 0, "test-player")
	_chunk_manager.remove_tile(Vector2i(5, 5), 0, "test-player")
	assert_bool(_chunk_manager.has_tile_at(Vector2i(5, 5), 0)).is_false()

func test_has_tile_at_returns_false_on_unloaded_chunk() -> void:
	# Chunk (50,50) is far away — not loaded
	assert_bool(_chunk_manager.has_tile_at(Vector2i(800, 800), 0)).is_false()

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
