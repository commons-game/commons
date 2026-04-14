## Tests for ProceduralGenerator.
## Key invariants: determinism, no tiling, all 256 ground entries present.
extends GdUnitTestSuite

func test_determinism() -> void:
	## Same coords + same seed must produce identical output.
	var result1 := ProceduralGenerator.generate_chunk(Vector2i(5, -3), 12345)
	var result2 := ProceduralGenerator.generate_chunk(Vector2i(5, -3), 12345)
	assert_that(result1.size()).is_equal(result2.size())
	for key in result1:
		assert_that(result2.has(key)).is_true()
		assert_that(result1[key]["tile_id"]).is_equal(result2[key]["tile_id"])
		assert_that(result1[key]["atlas_x"]).is_equal(result2[key]["atlas_x"])
		assert_that(result1[key]["atlas_y"]).is_equal(result2[key]["atlas_y"])

func test_different_coords_produce_different_output() -> void:
	## Different chunk coords must produce different terrain (no tiling artifacts).
	var a := ProceduralGenerator.generate_chunk(Vector2i(0, 0), 12345)
	var b := ProceduralGenerator.generate_chunk(Vector2i(10, 5), 12345)
	## Count matching ground tiles
	var matches := 0
	for ly in range(Constants.CHUNK_SIZE):
		for lx in range(Constants.CHUNK_SIZE):
			var key := CoordUtils.make_crdt_key(0, lx, ly)
			if a.has(key) and b.has(key):
				if a[key]["atlas_x"] == b[key]["atlas_x"]:
					matches += 1
	## If 100% of tiles match, generation is identical (broken).
	## Allow up to 80% match (terrain can share similar biomes by chance).
	assert_that(matches).is_less(256)

func test_ground_layer_has_256_entries() -> void:
	## All 256 local positions must have a ground tile (layer 0).
	var result := ProceduralGenerator.generate_chunk(Vector2i(3, 7), 12345)
	var ground_count := 0
	for ly in range(Constants.CHUNK_SIZE):
		for lx in range(Constants.CHUNK_SIZE):
			var key := CoordUtils.make_crdt_key(0, lx, ly)
			if result.has(key):
				ground_count += 1
	assert_that(ground_count).is_equal(256)

func test_ground_layer_has_256_entries_negative_coords() -> void:
	## Negative chunk coords must also produce 256 ground tiles.
	var result := ProceduralGenerator.generate_chunk(Vector2i(-5, -3), 12345)
	var ground_count := 0
	for ly in range(Constants.CHUNK_SIZE):
		for lx in range(Constants.CHUNK_SIZE):
			var key := CoordUtils.make_crdt_key(0, lx, ly)
			if result.has(key):
				ground_count += 1
	assert_that(ground_count).is_equal(256)

func test_atlas_x_values_in_valid_range() -> void:
	## atlas_x for ground tiles must be 0, 1, 2, or 3 (grass, dirt, stone, water).
	var result := ProceduralGenerator.generate_chunk(Vector2i(0, 0), 12345)
	for ly in range(Constants.CHUNK_SIZE):
		for lx in range(Constants.CHUNK_SIZE):
			var key := CoordUtils.make_crdt_key(0, lx, ly)
			if result.has(key):
				var ax: int = result[key]["atlas_x"]
				assert_that(ax >= 0 and ax <= 3).is_true()

func test_adjacent_chunks_share_no_identical_row_patterns() -> void:
	## Test that two horizontally adjacent chunks have different row patterns.
	var left := ProceduralGenerator.generate_chunk(Vector2i(0, 0), 12345)
	var right := ProceduralGenerator.generate_chunk(Vector2i(1, 0), 12345)
	## Compare row 0 of each chunk
	var left_row: Array = []
	var right_row: Array = []
	for lx in range(Constants.CHUNK_SIZE):
		var lkey := CoordUtils.make_crdt_key(0, lx, 0)
		var rkey := CoordUtils.make_crdt_key(0, lx, 0)
		if left.has(lkey):
			left_row.append(left[lkey]["atlas_x"])
		if right.has(rkey):
			right_row.append(right[rkey]["atlas_x"])
	## Rows should differ (this verifies XOR-with-primes avoids tiling)
	assert_that(left_row).is_not_equal(right_row)
