## Tests for MergePressureSystem — solo-time pressure accumulator.
## Rules:
##   - pressure ticks up when peer_count == 1 (solo).
##   - pressure is capped at 1.0.
##   - reset() drops pressure to reset_value (not zero — small residual).
##   - apply_talisman_modifier() scales ramp_rate multiplicatively.
##   - pressure does NOT tick when peer_count > 1 (already merged).
extends GdUnitTestSuite

const MergePressureScript := preload("res://networking/MergePressureSystem.gd")

func _make_system() -> Object:
	var s = MergePressureScript.new()
	return s

# --- Basic accumulation ---

func test_pressure_starts_at_zero() -> void:
	var s = _make_system()
	assert_that(s.pressure).is_equal(0.0)

func test_tick_solo_increases_pressure() -> void:
	var s = _make_system()
	s.peer_count = 1
	s.tick(1.0)
	assert_that(s.pressure).is_greater(0.0)

func test_tick_amount_matches_ramp_rate_times_delta() -> void:
	var s = _make_system()
	s.peer_count = 1
	s.tick(1.0)
	assert_that(s.pressure).is_equal(s.ramp_rate)

func test_tick_larger_delta_accumulates_more() -> void:
	var s = _make_system()
	s.peer_count = 1
	s.tick(10.0)
	assert_that(s.pressure).is_equal(s.ramp_rate * 10.0)

# --- Cap at 1.0 ---

func test_pressure_capped_at_one() -> void:
	var s = _make_system()
	s.peer_count = 1
	s.pressure = 0.999
	s.tick(1000.0)
	assert_that(s.pressure).is_equal(1.0)

# --- No tick when peers present ---

func test_pressure_does_not_tick_when_merged() -> void:
	var s = _make_system()
	s.peer_count = 2
	s.tick(100.0)
	assert_that(s.pressure).is_equal(0.0)

func test_pressure_does_not_tick_with_three_peers() -> void:
	var s = _make_system()
	s.peer_count = 3
	s.pressure = 0.5
	s.tick(10.0)
	assert_that(s.pressure).is_equal(0.5)

# --- Reset ---

func test_reset_drops_to_reset_value() -> void:
	var s = _make_system()
	s.pressure = 0.9
	s.reset()
	assert_that(s.pressure).is_equal(s.reset_value)

func test_reset_value_is_small_positive() -> void:
	var s = _make_system()
	assert_that(s.reset_value).is_greater(0.0)
	assert_that(s.reset_value).is_less(0.1)

# --- Talisman modifier ---

func test_talisman_modifier_scales_ramp_rate() -> void:
	var s = _make_system()
	var original_rate: float = s.ramp_rate
	s.apply_talisman_modifier(2.0)
	assert_that(s.ramp_rate).is_equal(original_rate * 2.0)

func test_talisman_modifier_affects_subsequent_ticks() -> void:
	var s = _make_system()
	s.peer_count = 1
	s.apply_talisman_modifier(3.0)
	s.tick(1.0)
	assert_that(s.pressure).is_equal(s.ramp_rate)  # ramp_rate already scaled

func test_talisman_modifier_stacks_multiplicatively() -> void:
	var s = _make_system()
	var base: float = s.ramp_rate
	s.apply_talisman_modifier(2.0)
	s.apply_talisman_modifier(2.0)
	assert_that(s.ramp_rate).is_equal(base * 4.0)
