## Tests for CoordUtils — coordinate conversions including negative coords.
## Run with gdUnit4. All tests must stay green for Phase 3 multiplayer.
extends GdUnitTestSuite

# --- world_to_chunk ---

func test_world_to_chunk_positive() -> void:
	assert_that(CoordUtils.world_to_chunk(Vector2i(0, 0))).is_equal(Vector2i(0, 0))
	assert_that(CoordUtils.world_to_chunk(Vector2i(15, 15))).is_equal(Vector2i(0, 0))
	assert_that(CoordUtils.world_to_chunk(Vector2i(16, 0))).is_equal(Vector2i(1, 0))
	assert_that(CoordUtils.world_to_chunk(Vector2i(31, 31))).is_equal(Vector2i(1, 1))
	assert_that(CoordUtils.world_to_chunk(Vector2i(32, 32))).is_equal(Vector2i(2, 2))
	assert_that(CoordUtils.world_to_chunk(Vector2i(1040, -500))).is_equal(Vector2i(65, -32))

func test_world_to_chunk_negative_one() -> void:
	# Critical: world_to_chunk(-1, -1) must return (-1, -1) NOT (0, 0).
	# GDScript % returns -1 for -1 % 16, but floor division returns -1.
	assert_that(CoordUtils.world_to_chunk(Vector2i(-1, -1))).is_equal(Vector2i(-1, -1))

func test_world_to_chunk_negative_boundary() -> void:
	# Tile (-16,-16) is exactly the top-left of chunk (-1,-1).
	assert_that(CoordUtils.world_to_chunk(Vector2i(-16, -16))).is_equal(Vector2i(-1, -1))
	# Tile (-17,-17) falls in chunk (-2,-2).
	assert_that(CoordUtils.world_to_chunk(Vector2i(-17, -17))).is_equal(Vector2i(-2, -2))

# --- world_to_local ---

func test_world_to_local_positive() -> void:
	assert_that(CoordUtils.world_to_local(Vector2i(0, 0))).is_equal(Vector2i(0, 0))
	assert_that(CoordUtils.world_to_local(Vector2i(16, 0))).is_equal(Vector2i(0, 0))
	assert_that(CoordUtils.world_to_local(Vector2i(17, 3))).is_equal(Vector2i(1, 3))

func test_world_to_local_negative() -> void:
	# Local coords are always [0, CHUNK_SIZE-1]
	assert_that(CoordUtils.world_to_local(Vector2i(-1, -1))).is_equal(Vector2i(15, 15))
	assert_that(CoordUtils.world_to_local(Vector2i(-16, -16))).is_equal(Vector2i(0, 0))

# --- chunk_local_to_world ---

func test_chunk_local_to_world() -> void:
	assert_that(CoordUtils.chunk_local_to_world(Vector2i(0, 0), Vector2i(0, 0))).is_equal(Vector2i(0, 0))
	assert_that(CoordUtils.chunk_local_to_world(Vector2i(1, 0), Vector2i(5, 3))).is_equal(Vector2i(21, 3))
	assert_that(CoordUtils.chunk_local_to_world(Vector2i(-1, -1), Vector2i(0, 0))).is_equal(Vector2i(-16, -16))
	assert_that(CoordUtils.chunk_local_to_world(Vector2i(-1, -1), Vector2i(15, 15))).is_equal(Vector2i(-1, -1))

# --- round-trip test ---

func test_round_trip_positive() -> void:
	var points := [Vector2i(0, 0), Vector2i(1, 1), Vector2i(15, 15),
	               Vector2i(16, 16), Vector2i(100, 200), Vector2i(1040, -500)]
	for p in points:
		var recovered := CoordUtils.chunk_local_to_world(
		    CoordUtils.world_to_chunk(p), CoordUtils.world_to_local(p))
		assert_that(recovered).is_equal(p)

func test_round_trip_negative() -> void:
	var points := [Vector2i(-1, -1), Vector2i(-16, -16), Vector2i(-17, -17),
	               Vector2i(-100, -200), Vector2i(-1, 5), Vector2i(5, -1)]
	for p in points:
		var recovered := CoordUtils.chunk_local_to_world(
		    CoordUtils.world_to_chunk(p), CoordUtils.world_to_local(p))
		assert_that(recovered).is_equal(p)

# --- make_crdt_key ---

func test_make_crdt_key() -> void:
	# Layer 0, lx=0, ly=0 -> 0
	assert_that(CoordUtils.make_crdt_key(0, 0, 0)).is_equal(0)
	# Layer 1, lx=0, ly=0 -> (1 << 16) = 65536
	assert_that(CoordUtils.make_crdt_key(1, 0, 0)).is_equal(65536)
	# Layer 0, lx=5, ly=3 -> (5 << 8) | 3 = 1283
	assert_that(CoordUtils.make_crdt_key(0, 5, 3)).is_equal(1283)
	# Layer 1, lx=15, ly=15 -> 65536 | (15 << 8) | 15 = 65536 | 3840 | 15
	assert_that(CoordUtils.make_crdt_key(1, 15, 15)).is_equal(65536 | 3840 | 15)
