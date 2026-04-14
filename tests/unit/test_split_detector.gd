## Tests for SplitDetector — monitors bridge usage, triggers dissolution when sessions drift.
##
## Rules:
##   - should_dissolve() returns true when the two session positions are farther
##     apart than SPLIT_DISTANCE (Chebyshev chunks).
##   - Sessions within SPLIT_DISTANCE never dissolve.
##   - on_dissolve() resets MergePressureSystem to reset_value.
extends GdUnitTestSuite

const SplitDetectorScript  := preload("res://networking/SplitDetector.gd")
const MergePressureScript  := preload("res://networking/MergePressureSystem.gd")

func _make_detector() -> Object:
	return SplitDetectorScript.new()

# --- should_dissolve ---

func test_close_sessions_do_not_dissolve() -> void:
	var sd = _make_detector()
	assert_bool(sd.should_dissolve(Vector2i(0, 0), Vector2i(5, 0))).is_false()

func test_far_sessions_dissolve() -> void:
	var sd = _make_detector()
	# SPLIT_DISTANCE is 25; place sessions 30 apart
	assert_bool(sd.should_dissolve(Vector2i(0, 0), Vector2i(30, 0))).is_true()

func test_exactly_at_split_distance_does_not_dissolve() -> void:
	var sd = _make_detector()
	assert_bool(sd.should_dissolve(Vector2i(0, 0),
		Vector2i(sd.SPLIT_DISTANCE, 0))).is_false()

func test_one_beyond_split_distance_dissolves() -> void:
	var sd = _make_detector()
	assert_bool(sd.should_dissolve(Vector2i(0, 0),
		Vector2i(sd.SPLIT_DISTANCE + 1, 0))).is_true()

func test_diagonal_distance_uses_chebyshev() -> void:
	var sd = _make_detector()
	# Chebyshev distance of (20,20) from origin is 20 — within SPLIT_DISTANCE(25)
	assert_bool(sd.should_dissolve(Vector2i(0, 0), Vector2i(20, 20))).is_false()

# --- on_dissolve resets pressure ---

func test_on_dissolve_resets_pressure_system() -> void:
	var sd = _make_detector()
	var pressure = MergePressureScript.new()
	pressure.peer_count = 1
	pressure.tick(1000.0)
	assert_that(pressure.pressure).is_equal(1.0)

	sd.on_dissolve(pressure)
	assert_that(pressure.pressure).is_equal(pressure.reset_value)

func test_on_dissolve_can_be_called_with_null_pressure() -> void:
	var sd = _make_detector()
	sd.on_dissolve(null)  # graceful no-op
