## Tests for TileRegistry — tile name → tileset data resolution.
extends GdUnitTestSuite

func test_resolve_registered_tile() -> void:
	TileRegistry.register("stone", 0, Vector2i(1, 2), 0)
	var entry := TileRegistry.resolve("stone")
	assert_that(entry.is_empty()).is_false()
	assert_int(entry["tile_id"]).is_equal(0)
	assert_int(entry["atlas"].x).is_equal(1)
	assert_int(entry["atlas"].y).is_equal(2)
	assert_int(entry["alt"]).is_equal(0)

func test_resolve_unknown_returns_empty() -> void:
	var entry := TileRegistry.resolve("no_such_tile")
	assert_that(entry.is_empty()).is_true()

func test_has_registered_tile() -> void:
	TileRegistry.register("dirt", 0, Vector2i(0, 0), 0)
	assert_bool(TileRegistry.has_tile("dirt")).is_true()

func test_has_unknown_tile() -> void:
	assert_bool(TileRegistry.has_tile("phantom")).is_false()

func test_register_overwrites() -> void:
	TileRegistry.register("grass", 0, Vector2i(0, 0), 0)
	TileRegistry.register("grass", 1, Vector2i(3, 4), 2)
	var entry := TileRegistry.resolve("grass")
	assert_int(entry["tile_id"]).is_equal(1)
	assert_int(entry["atlas"].x).is_equal(3)
	assert_int(entry["alt"]).is_equal(2)
