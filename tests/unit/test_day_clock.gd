## Tests for DayClock — shared real-time day/night cycle.
##
## Rules:
##   - DAY_CYCLE_SECONDS = 7200 (60 min day + 60 min night)
##   - Phase 0-0.5: daytime. Phase 0.5-1.0: nighttime.
##   - phase_fraction() returns position [0,1] within full cycle.
##   - is_daytime() returns true when phase_fraction < 0.5.
##   - sky_alpha() returns 0.0 (full light) during day, 1.0 (full dark) at midnight.
##   - Supports _time_override so tests don't depend on wall-clock.
##   - phase_changed(is_day: bool) signal fires on day/night transition.
extends GdUnitTestSuite

const DayClockScript := preload("res://autoloads/DayClock.gd")

func _make_clock(unix_time: float = 0.0) -> Object:
	var c = DayClockScript.new()
	c._time_override = unix_time
	return c

# --- Phase fraction ---

func test_phase_fraction_zero_at_start_of_cycle() -> void:
	var c = _make_clock(0.0)
	assert_float(c.phase_fraction()).is_equal(0.0)

func test_phase_fraction_half_at_3600() -> void:
	var c = _make_clock(3600.0)
	assert_float(c.phase_fraction()).is_equal(0.5)

func test_phase_fraction_wraps_at_cycle_boundary() -> void:
	var c = _make_clock(7200.0)
	assert_float(c.phase_fraction()).is_equal(0.0)

func test_phase_fraction_is_normalized_0_to_1() -> void:
	var c = _make_clock(1800.0)
	assert_float(c.phase_fraction()).is_greater_equal(0.0)
	assert_float(c.phase_fraction()).is_less(1.0)

func test_phase_fraction_large_unix_time_wraps() -> void:
	# unix time far in the future should still wrap correctly
	var c = _make_clock(86400.0 + 1800.0)  # 24 hours + 1800 s
	assert_float(c.phase_fraction()).is_equal_approx(0.25, 0.0001)

# --- is_daytime ---

func test_is_daytime_at_start_of_cycle() -> void:
	var c = _make_clock(0.0)
	assert_bool(c.is_daytime()).is_true()

func test_is_daytime_at_noon() -> void:
	var c = _make_clock(1800.0)
	assert_bool(c.is_daytime()).is_true()

func test_is_nighttime_at_dusk() -> void:
	var c = _make_clock(3600.0)
	assert_bool(c.is_daytime()).is_false()

func test_is_nighttime_at_midnight() -> void:
	var c = _make_clock(5400.0)
	assert_bool(c.is_daytime()).is_false()

func test_becomes_day_again_near_cycle_end() -> void:
	var c = _make_clock(7199.0)
	assert_bool(c.is_daytime()).is_false()

# --- sky_alpha (darkness overlay alpha) ---
# 0.0 = full daylight (midday), 1.0 = full dark (midnight)

func test_sky_alpha_zero_at_midday() -> void:
	var c = _make_clock(1800.0)  # midday = 1/4 through cycle
	assert_float(c.sky_alpha()).is_equal_approx(0.0, 0.01)

func test_sky_alpha_max_at_midnight() -> void:
	var c = _make_clock(5400.0)  # midnight = 3/4 through cycle
	assert_float(c.sky_alpha()).is_equal_approx(1.0, 0.01)

func test_sky_alpha_halfway_at_dusk() -> void:
	var c = _make_clock(3600.0)  # dusk = halfway
	# At the exact phase boundary (0.5) alpha should be near 0.5
	assert_float(c.sky_alpha()).is_greater_equal(0.4)
	assert_float(c.sky_alpha()).is_less_equal(0.6)

func test_sky_alpha_clamped_0_to_1() -> void:
	var c = _make_clock(0.0)
	assert_float(c.sky_alpha()).is_greater_equal(0.0)
	assert_float(c.sky_alpha()).is_less_equal(1.0)

# --- phase_changed signal ---

func test_phase_changed_fires_on_night_transition() -> void:
	var c = _make_clock(3599.0)  # just before dusk
	add_child(c)
	var fired: Array = [false]
	var is_day_value: Array = [true]
	c.phase_changed.connect(func(is_day: bool):
		fired[0] = true
		is_day_value[0] = is_day)
	# Advance time past dusk
	c._time_override = 3601.0
	c.tick(0.1)
	assert_bool(fired[0]).is_true()
	assert_bool(is_day_value[0]).is_false()
	remove_child(c)

func test_phase_changed_fires_on_day_transition() -> void:
	var c = _make_clock(7199.0)  # just before dawn
	add_child(c)
	var fired: Array = [false]
	var is_day_value: Array = [false]
	c.phase_changed.connect(func(is_day: bool):
		fired[0] = true
		is_day_value[0] = is_day)
	c._time_override = 7201.0  # wraps to early day (7201 % 7200 = 1)
	c.tick(0.1)
	assert_bool(fired[0]).is_true()
	assert_bool(is_day_value[0]).is_true()
	remove_child(c)

func test_phase_changed_does_not_fire_when_same_phase() -> void:
	var c = _make_clock(100.0)  # daytime
	add_child(c)
	var calls: Array = [0]
	c.phase_changed.connect(func(_d): calls[0] += 1)
	c._time_override = 200.0   # still daytime
	c.tick(0.1)
	assert_int(calls[0]).is_equal(0)
	remove_child(c)
