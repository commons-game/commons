## Tests for ShiftingLandsSystem: drift logic, split/merge lifecycle.
extends GdUnitTestSuite

const ShiftingLandsScript := preload("res://world/ShiftingLandsSystem.gd")

var _sys: Object

func before_test() -> void:
	_sys = ShiftingLandsScript.new()

func after_test() -> void:
	if is_instance_valid(_sys):
		_sys.free()

func test_not_split_initially() -> void:
	assert_bool(_sys.is_split()).is_false()

func test_not_shifted_when_not_split() -> void:
	assert_bool(_sys.is_chunk_shifted(Vector2i(5, 5))).is_false()

func test_split_marks_as_split() -> void:
	_sys._on_split_occurred("test-remote-session")
	assert_bool(_sys.is_split()).is_true()

func test_no_drift_within_delay() -> void:
	_sys._on_split_occurred("test-remote-session")
	var all_stable := true
	for i in 50:
		if _sys.is_chunk_shifted(Vector2i(i, i)):
			all_stable = false
			break
	assert_bool(all_stable).is_true()

func test_merge_clears_split_state() -> void:
	_sys._on_split_occurred("test-remote-session")
	_sys._on_merge_ready("test-remote-session")
	assert_bool(_sys.is_split()).is_false()

func test_merge_clears_drift_cache() -> void:
	_sys._on_split_occurred("test-remote-session")
	_sys._drifted[Vector2i(3, 3)] = true
	_sys._on_merge_ready("test-remote-session")
	assert_int(_sys._drifted.size()).is_equal(0)

func test_split_seed_differs_for_different_partner_ids() -> void:
	_sys._on_split_occurred("session-abc")
	var seed_a: int = _sys.get_shift_seed()
	_sys._on_split_occurred("session-xyz")
	var seed_b: int = _sys.get_shift_seed()
	assert_bool(seed_a != seed_b).is_true()

func test_get_drifted_coords_empty_before_split() -> void:
	assert_int(_sys.get_drifted_coords().size()).is_equal(0)

func test_get_drifted_coords_returns_marked() -> void:
	_sys._drifted[Vector2i(1, 2)] = true
	_sys._drifted[Vector2i(3, 4)] = false
	var drifted: Array = _sys.get_drifted_coords()
	assert_int(drifted.size()).is_equal(1)
	assert_bool(drifted.has(Vector2i(1, 2))).is_true()

func test_drift_decision_cached() -> void:
	_sys._on_split_occurred("test-remote-session")
	_sys._split_time = Time.get_unix_time_from_system() - 30.0
	var coords := Vector2i(7, 7)
	var first: bool = _sys.is_chunk_shifted(coords)
	var second: bool = _sys.is_chunk_shifted(coords)
	assert_bool(first == second).is_true()

func test_shifted_chunk_has_more_water_than_normal() -> void:
	var normal := ProceduralGenerator.generate_chunk(Vector2i(0, 0), 12345)
	var shifted := ProceduralGenerator.generate_shifted_chunk(Vector2i(0, 0), 12345, 99999)
	var normal_water := 0
	var shifted_water := 0
	for key in normal:
		if normal[key].get("atlas_x", -1) == 3:
			normal_water += 1
	for key in shifted:
		if shifted[key].get("atlas_x", -1) == 3:
			shifted_water += 1
	assert_bool(shifted_water > normal_water).is_true()
