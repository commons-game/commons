## Tests for DayClockInstance — the standalone (non-autoload) clock.
##
## Phase 0a of the per-island clock refactor: the time-of-day logic now
## lives in a RefCounted instance so multiple clocks (one per island) can
## coexist. The autoload `DayClock` becomes a thin wrapper around one of
## these. These tests exercise the instance directly, not through the
## autoload — see test_day_clock.gd for the autoload-API coverage.
##
## Coverage focuses on the behaviours most likely to break in extraction:
##   - phase_fraction / is_daytime / sky_alpha at known unix anchors
##   - advance_to_phase forward-only invariant + boundary wrap
##   - moon_phase / moon_fullness / day_count interaction
##   - phase_changed signal emits from the instance (not the autoload)
extends GdUnitTestSuite

const DayClockInstanceScript := preload("res://world/DayClockInstance.gd")

func _make_clock(unix_time: float = 0.0):
	var c = DayClockInstanceScript.new()
	c._time_override = unix_time
	return c

# --- phase_fraction / is_daytime ---

func test_instance_phase_zero_at_cycle_start() -> void:
	var c = _make_clock(0.0)
	assert_float(c.phase_fraction()).is_equal(0.0)
	assert_bool(c.is_daytime()).is_true()

func test_instance_phase_half_at_dusk() -> void:
	var c = _make_clock(3600.0)
	assert_float(c.phase_fraction()).is_equal(0.5)
	assert_bool(c.is_daytime()).is_false()

func test_instance_phase_wraps_at_cycle_boundary() -> void:
	var c = _make_clock(7200.0)
	assert_float(c.phase_fraction()).is_equal(0.0)

# --- sky_alpha smoothness around the day/night boundary ---

func test_instance_sky_alpha_zero_at_midday() -> void:
	var c = _make_clock(1800.0)
	assert_float(c.sky_alpha()).is_equal_approx(0.0, 0.01)

func test_instance_sky_alpha_max_at_midnight() -> void:
	var c = _make_clock(5400.0)
	assert_float(c.sky_alpha()).is_equal_approx(1.0, 0.01)

func test_instance_sky_alpha_continuous_across_dusk() -> void:
	# Just before and just after dusk should be near 0.5 (smooth, no jump).
	var before = _make_clock(3500.0)
	var at_dusk = _make_clock(3600.0)
	var after = _make_clock(3700.0)
	assert_float(at_dusk.sky_alpha()).is_equal_approx(0.5, 0.05)
	assert_float(abs(before.sky_alpha() - at_dusk.sky_alpha())).is_less(0.05)
	assert_float(abs(after.sky_alpha() - at_dusk.sky_alpha())).is_less(0.05)

# --- advance_to_phase: monotonic forward ---

func test_instance_advance_to_phase_lands_on_phase() -> void:
	var c = _make_clock(720.0)  # phase 0.1
	c.advance_to_phase(0.25)
	assert_float(c.phase_fraction()).is_equal_approx(0.25, 0.001)

func test_instance_advance_never_rewinds() -> void:
	# From midday (phase 0.25) ask for dawn (0.0) — should wrap forward, not rewind.
	var c = _make_clock(1800.0)
	var before: float = c._get_unix_time()
	c.advance_to_phase(0.0)
	var after: float = c._get_unix_time()
	assert_float(after).is_greater(before)
	assert_float(c.phase_fraction()).is_equal_approx(0.0, 0.001)

# --- moon_phase / day_count interaction ---

func test_instance_moon_phase_advances_with_day_count() -> void:
	var c = _make_clock(Constants.DAY_CYCLE_SECONDS * 4.0)
	assert_int(c.day_count()).is_equal(4)
	assert_int(c.moon_phase()).is_equal(4)
	assert_float(c.moon_fullness()).is_equal_approx(1.0, 0.001)

func test_instance_moon_phase_cycles_every_8_days() -> void:
	var c = _make_clock(Constants.DAY_CYCLE_SECONDS * 8.0)
	assert_int(c.day_count()).is_equal(8)
	assert_int(c.moon_phase()).is_equal(0)

# --- phase_changed signal lives on the instance ---

func test_instance_emits_phase_changed_on_dusk_crossing() -> void:
	var c = _make_clock(3599.0)
	var fired: Array = [false]
	var seen_is_day: Array = [true]
	c.phase_changed.connect(func(is_day: bool):
		fired[0] = true
		seen_is_day[0] = is_day)
	c._time_override = 3601.0
	c.tick(0.1)
	assert_bool(fired[0]).is_true()
	assert_bool(seen_is_day[0]).is_false()

func test_instance_does_not_emit_on_same_phase_tick() -> void:
	var c = _make_clock(100.0)
	var calls: Array = [0]
	c.phase_changed.connect(func(_d): calls[0] += 1)
	c._time_override = 200.0
	c.tick(0.1)
	assert_int(calls[0]).is_equal(0)

# --- multiple instances are independent ---

func test_two_instances_have_independent_state() -> void:
	# This is the whole point of the extraction — each island gets its own clock.
	var a = _make_clock(0.0)
	var b = _make_clock(5400.0)
	assert_bool(a.is_daytime()).is_true()
	assert_bool(b.is_daytime()).is_false()
	# Mutating one must not affect the other.
	a.advance_to_phase(0.5)
	assert_bool(b.is_daytime()).is_false()  # still pinned at 5400
	assert_float(b.phase_fraction()).is_equal_approx(0.75, 0.001)
