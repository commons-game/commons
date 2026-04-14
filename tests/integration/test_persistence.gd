## Integration tests for LocalBackend persistence round-trip.
## Writes chunk data, reads it back, verifies correctness.
## Cleans up all test files in teardown.
extends GdUnitTestSuite

const LocalBackendScript := preload("res://backend/local/LocalBackend.gd")
const TEST_DIR := "user://chunks_test/"

var _backend

func before_test() -> void:
	_backend = LocalBackendScript.new()
	# Use a test-specific dir so we don't pollute real game saves.
	_backend.initialize(TEST_DIR)

func after_test() -> void:
	# Clean up test files.
	var dir := DirAccess.open(TEST_DIR)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				DirAccess.remove_absolute(TEST_DIR + fname)
			fname = dir.get_next()
	DirAccess.remove_absolute(TEST_DIR)

# Helper: build a minimal chunk JSON payload as PackedByteArray.
func _make_chunk_bytes(cx: int, cy: int) -> PackedByteArray:
	var entries := [
		{"layer": 0, "lx": 3, "ly": 7,
		 "tile_id": 2, "atlas_x": 1, "atlas_y": 0, "alt_tile": 0,
		 "timestamp": 1744567890.0, "author_id": "test-player"},
		{"layer": 1, "lx": 8, "ly": 2,
		 "tile_id": -1, "atlas_x": 0, "atlas_y": 0, "alt_tile": 0,
		 "timestamp": 1744567891.0, "author_id": "test-player"}
	]
	return JSON.stringify({"chunk_x": cx, "chunk_y": cy,
		"world_seed": 12345, "version": 1, "entries": entries}).to_utf8_buffer()

# --- round-trip: store then retrieve ---

func test_store_and_retrieve_positive_coords() -> void:
	var coords := Vector2i(5, 3)
	var data := _make_chunk_bytes(coords.x, coords.y)
	_backend.store_chunk(coords, data)
	var retrieved: PackedByteArray = _backend.retrieve_chunk(coords)
	assert_that(retrieved.is_empty()).is_false()
	var parsed: Dictionary = JSON.parse_string(retrieved.get_string_from_utf8())
	assert_that(parsed).is_not_null()
	assert_that(int(parsed["chunk_x"])).is_equal(5)
	assert_that(int(parsed["chunk_y"])).is_equal(3)
	assert_that((parsed["entries"] as Array).size()).is_equal(2)

func test_store_and_retrieve_negative_coords() -> void:
	var coords := Vector2i(-3, -12)
	var data := _make_chunk_bytes(coords.x, coords.y)
	_backend.store_chunk(coords, data)
	var retrieved: PackedByteArray = _backend.retrieve_chunk(coords)
	assert_that(retrieved.is_empty()).is_false()
	var parsed: Dictionary = JSON.parse_string(retrieved.get_string_from_utf8())
	assert_that(int(parsed["chunk_x"])).is_equal(-3)
	assert_that(int(parsed["chunk_y"])).is_equal(-12)

# --- retrieve missing chunk returns empty ---

func test_retrieve_missing_returns_empty() -> void:
	var coords := Vector2i(99, 99)
	var result: PackedByteArray = _backend.retrieve_chunk(coords)
	assert_that(result.is_empty()).is_true()

# --- delete removes the file ---

func test_delete_chunk_removes_file() -> void:
	var coords := Vector2i(1, 1)
	_backend.store_chunk(coords, _make_chunk_bytes(coords.x, coords.y))
	assert_that(_backend.retrieve_chunk(coords).is_empty()).is_false()
	_backend.delete_chunk(coords)
	assert_that(_backend.retrieve_chunk(coords).is_empty()).is_true()

# --- tombstone entry survives round-trip ---

func test_tombstone_entry_survives_round_trip() -> void:
	var coords := Vector2i(2, 2)
	var data := _make_chunk_bytes(coords.x, coords.y)
	_backend.store_chunk(coords, data)
	var parsed: Dictionary = JSON.parse_string(
		_backend.retrieve_chunk(coords).get_string_from_utf8())
	var entries := parsed["entries"] as Array
	var tombstone := entries.filter(func(e): return e["tile_id"] == -1)
	assert_that(tombstone.size()).is_equal(1)
	assert_that(tombstone[0]["author_id"]).is_equal("test-player")
