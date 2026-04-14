## Unit tests for LocalBackend reputation persistence.
## Uses a temp directory so tests don't pollute real user:// data.
extends GdUnitTestSuite

const LocalBackendScript := preload("res://backend/local/LocalBackend.gd")

var _backend: Object

func before_test() -> void:
	_backend = LocalBackendScript.new()
	# Use a unique temp dir per test to avoid cross-test pollution
	_backend.initialize("user://test_rep_%d/" % randi())

func after_test() -> void:
	if _backend != null:
		if FileAccess.file_exists(_backend.reputation_path):
			DirAccess.remove_absolute(_backend.reputation_path)
	_backend = null

func test_load_missing_returns_empty_dict() -> void:
	var loaded: Dictionary = _backend.load_reputation()
	assert_that(loaded.size()).is_equal(0)

func test_save_and_load_roundtrip() -> void:
	var data: Dictionary = {
		"records":   {"player_x": {"report_count": 2, "in_chaos_pool": false}},
		"reporters": {"player_x": {"reporter_1": true, "reporter_2": true}}
	}
	_backend.save_reputation(data)
	var loaded: Dictionary = _backend.load_reputation()
	assert_bool(loaded.has("records")).is_true()
	assert_bool(loaded["records"].has("player_x")).is_true()
	assert_that(int(loaded["records"]["player_x"]["report_count"])).is_equal(2)
	assert_bool(bool(loaded["records"]["player_x"]["in_chaos_pool"])).is_false()

func test_save_overwrites_previous() -> void:
	_backend.save_reputation({
		"records": {"alice": {"report_count": 1, "in_chaos_pool": false}},
		"reporters": {}
	})
	_backend.save_reputation({
		"records": {"bob": {"report_count": 5, "in_chaos_pool": true}},
		"reporters": {}
	})
	var loaded: Dictionary = _backend.load_reputation()
	assert_bool(loaded["records"].has("bob")).is_true()
	assert_bool(loaded["records"].has("alice")).is_false()

func test_malformed_file_returns_empty_dict() -> void:
	# Write garbage to the reputation file
	var file := FileAccess.open(_backend.reputation_path, FileAccess.WRITE)
	if file:
		file.store_string("not json {{{")
		file.close()
	var loaded: Dictionary = _backend.load_reputation()
	assert_that(loaded.size()).is_equal(0)
