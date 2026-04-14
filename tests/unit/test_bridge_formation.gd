## Tests for BridgeFormation — when and where bridge chunks appear between sessions.
##
## Rules:
##   - should_form_bridge() returns true when pressure >= threshold AND
##     sessions are within BRIDGE_MAX_DISTANCE chunks of each other.
##   - pressure=1.0 always passes the probability gate (test deterministically).
##   - pressure=0.0 never passes.
##   - Sessions farther than BRIDGE_MAX_DISTANCE apart never bridge.
##   - get_bridge_chunks() returns the straight-line intermediate chunks
##     between two session positions (excluding endpoints).
##   - Adjacent positions have no intermediate chunks (empty bridge).
##   - Same position returns empty.
extends GdUnitTestSuite

const BridgeFormationScript := preload("res://networking/BridgeFormation.gd")

func _make_formation() -> Object:
	return BridgeFormationScript.new()

# --- should_form_bridge ---

func test_high_pressure_close_sessions_forms_bridge() -> void:
	var bf = _make_formation()
	assert_bool(bf.should_form_bridge(Vector2i(0, 0), Vector2i(3, 0), 1.0, 1.0)).is_true()

func test_zero_pressure_never_forms_bridge() -> void:
	var bf = _make_formation()
	for _i in range(20):
		assert_bool(bf.should_form_bridge(Vector2i(0, 0), Vector2i(3, 0), 0.0, 0.0)).is_false()

func test_sessions_too_far_apart_never_bridge() -> void:
	var bf = _make_formation()
	# BRIDGE_MAX_DISTANCE is 20 — place sessions 50 chunks apart
	assert_bool(bf.should_form_bridge(Vector2i(0, 0), Vector2i(50, 0), 1.0, 1.0)).is_false()

func test_sessions_exactly_at_max_distance_can_bridge() -> void:
	var bf = _make_formation()
	# Exactly at the limit with full pressure — should be eligible
	assert_bool(bf.should_form_bridge(Vector2i(0, 0),
		Vector2i(bf.BRIDGE_MAX_DISTANCE, 0), 1.0, 1.0)).is_true()

func test_at_least_one_pressure_zero_never_bridges() -> void:
	# Both pressures must be above zero for bridge to form
	var bf = _make_formation()
	for _i in range(10):
		assert_bool(bf.should_form_bridge(Vector2i(0, 0), Vector2i(3, 0), 1.0, 0.0)).is_false()
		assert_bool(bf.should_form_bridge(Vector2i(0, 0), Vector2i(3, 0), 0.0, 1.0)).is_false()

# --- get_bridge_chunks ---

func test_same_position_returns_empty() -> void:
	var bf = _make_formation()
	assert_that(bf.get_bridge_chunks(Vector2i(0, 0), Vector2i(0, 0)).size()).is_equal(0)

func test_adjacent_positions_returns_empty() -> void:
	var bf = _make_formation()
	assert_that(bf.get_bridge_chunks(Vector2i(0, 0), Vector2i(1, 0)).size()).is_equal(0)

func test_two_apart_returns_one_intermediate() -> void:
	var bf = _make_formation()
	var chunks: Array = bf.get_bridge_chunks(Vector2i(0, 0), Vector2i(2, 0))
	assert_that(chunks.size()).is_equal(1)
	assert_that(chunks[0]).is_equal(Vector2i(1, 0))

func test_four_apart_returns_three_intermediates() -> void:
	var bf = _make_formation()
	var chunks: Array = bf.get_bridge_chunks(Vector2i(0, 0), Vector2i(4, 0))
	assert_that(chunks.size()).is_equal(3)

func test_bridge_chunks_do_not_include_endpoints() -> void:
	var bf = _make_formation()
	var chunks: Array = bf.get_bridge_chunks(Vector2i(0, 0), Vector2i(3, 0))
	assert_bool(chunks.has(Vector2i(0, 0))).is_false()
	assert_bool(chunks.has(Vector2i(3, 0))).is_false()

func test_vertical_bridge_path() -> void:
	var bf = _make_formation()
	var chunks: Array = bf.get_bridge_chunks(Vector2i(0, 0), Vector2i(0, 3))
	assert_that(chunks.size()).is_equal(2)
	assert_bool(chunks.has(Vector2i(0, 1))).is_true()
	assert_bool(chunks.has(Vector2i(0, 2))).is_true()
