## Integration tests for GravestoneScatter and get_ground_atlas_at.
##
## Covers the behaviors identified in the gravestone world-gen retrospective:
##   1. get_ground_atlas_at returns correct atlas for a loaded ground tile
##   2. get_ground_atlas_at returns (-1,-1) for an unloaded chunk
##   3. Gravestone tiles (atlas 2,1) can be placed and detected via has_tile_at
##   4. Scatter places at least one gravestone in a loaded region
##   5. Scatter does not place on water ground tiles
##   6. Scatter does not clobber existing object tiles
extends GdUnitTestSuite

const GravestoneScatterScript := preload("res://world/generation/GravestoneScatter.gd")

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
# get_ground_atlas_at
# ---------------------------------------------------------------------------

func test_get_ground_atlas_at_unloaded_returns_negative() -> void:
	# Chunk (999, 999) is far away and not loaded.
	var result := _cm.get_ground_atlas_at(Vector2i(999 * Constants.CHUNK_SIZE, 0))
	assert_int(result.x).is_equal(-1)
	assert_int(result.y).is_equal(-1)

func test_get_ground_atlas_at_returns_placed_ground_tile_atlas() -> void:
	# Force a known ground tile at (0,0) (layer 0, atlas (1,0) = dirt).
	_cm.place_tile(Vector2i(0, 0), 0, 0, Vector2i(1, 0), 0, "test")
	var result := _cm.get_ground_atlas_at(Vector2i(0, 0))
	assert_int(result.x).is_equal(1)
	assert_int(result.y).is_equal(0)

# ---------------------------------------------------------------------------
# Gravestone placement primitive
# ---------------------------------------------------------------------------

func test_gravestone_tile_placed_and_detected() -> void:
	# A gravestone at atlas (2,1) on the object layer must be detectable via has_tile_at.
	var pos := Vector2i(2, 2)
	# Clear any procedurally-generated object tile first
	_cm.remove_tile(pos, 1, "setup")
	_cm.place_tile(pos, 1, 0, Vector2i(2, 1), 0, "test")
	assert_bool(_cm.has_tile_at(pos, 1)).is_true()
	# Verify the CRDT record stores the correct atlas coords
	var chunk := _cm.get_chunk(CoordUtils.world_to_chunk(pos))
	var local := CoordUtils.world_to_local(pos)
	var tile := chunk.crdt.get_tile(1, local)
	assert_int(tile["atlas_x"]).is_equal(2)
	assert_int(tile["atlas_y"]).is_equal(1)

# ---------------------------------------------------------------------------
# Scatter behaviour
# ---------------------------------------------------------------------------

func test_scatter_places_at_least_one_gravestone() -> void:
	# With chunks loaded around origin, scatter must place at least 1 gravestone.
	var placed := GravestoneScatterScript.scatter(_cm, Vector2i.ZERO, Constants.WORLD_SEED)
	assert_int(placed).is_greater(0)

func test_scatter_does_not_place_on_water() -> void:
	# Fill the origin chunk with water on ground layer + clear all objects.
	# With chunk_radius=0 the scatter only samples origin-chunk tiles — all water → 0 placed.
	for lx in range(Constants.CHUNK_SIZE):
		for ly in range(Constants.CHUNK_SIZE):
			var wpos := Vector2i(lx, ly)
			_cm.place_tile(wpos, 0, 0, Vector2i(3, 0), 0, "test")  # water
			_cm.remove_tile(wpos, 1, "test")                         # clear objects
	var placed := GravestoneScatterScript.scatter(_cm, Vector2i.ZERO, Constants.WORLD_SEED,
	                                               10, 0)  # radius=0 → only origin chunk tiles
	assert_int(placed).is_equal(0)

func test_scatter_does_not_clobber_existing_object_tile() -> void:
	# Fill every tile in chunk (0,0) on the object layer with trees, then scatter.
	# All positions are occupied → scatter must place 0 gravestones.
	for lx in range(Constants.CHUNK_SIZE):
		for ly in range(Constants.CHUNK_SIZE):
			_cm.place_tile(Vector2i(lx, ly), 1, 0, Vector2i(0, 1), 0, "test")  # tree
	var placed := GravestoneScatterScript.scatter(_cm, Vector2i.ZERO, Constants.WORLD_SEED,
	                                               10, 0)  # radius=0 → only origin chunk tiles
	assert_int(placed).is_equal(0)
