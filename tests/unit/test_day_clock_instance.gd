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
	# resync_phase() re-seeds _last_is_day from the now-pinned time. Without
	# this the seed in _init() reads wall-clock time (because _time_override
	# was still -1.0 at that point), and any subsequent transition test is
	# flaky depending on what the real wall clock happens to say. The
	# autoload-Phase-0a wrapper used to call resync_phase() in its own
	# _ready() to paper over this; helpers that mutate _time_override
	# out-of-band must do the same.
	c.resync_phase()
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

# ---------------------------------------------------------------------------
# Phase 0c migration: cases moved here from test_day_clock.gd, which used
# to construct the autoload script via `.new()` and treat it as a node. The
# autoload is now a thin shim with no state of its own — the timekeeping
# behaviour these cases pin lives on DayClockInstance, so they belong here.
# ---------------------------------------------------------------------------

# --- phase_fraction edge cases ---

func test_instance_phase_fraction_is_normalized_0_to_1() -> void:
	var c = _make_clock(1800.0)
	assert_float(c.phase_fraction()).is_greater_equal(0.0)
	assert_float(c.phase_fraction()).is_less(1.0)

func test_instance_phase_fraction_large_unix_time_wraps() -> void:
	# unix time far in the future should still wrap correctly
	var c = _make_clock(86400.0 + 1800.0)  # 24 hours + 1800 s
	assert_float(c.phase_fraction()).is_equal_approx(0.25, 0.0001)

# --- is_daytime at every quadrant of the cycle ---

func test_instance_is_daytime_at_noon() -> void:
	var c = _make_clock(1800.0)
	assert_bool(c.is_daytime()).is_true()

func test_instance_is_nighttime_at_midnight() -> void:
	var c = _make_clock(5400.0)
	assert_bool(c.is_daytime()).is_false()

func test_instance_becomes_day_again_near_cycle_end() -> void:
	# Just before the cycle wraps (which lands us at dawn = day) we should
	# still be reading as nighttime.
	var c = _make_clock(7199.0)
	assert_bool(c.is_daytime()).is_false()

# --- sky_alpha bounds ---

func test_instance_sky_alpha_clamped_0_to_1() -> void:
	var c = _make_clock(0.0)
	assert_float(c.sky_alpha()).is_greater_equal(0.0)
	assert_float(c.sky_alpha()).is_less_equal(1.0)

# --- phase_changed: day-direction transition (was night-only above) ---

func test_instance_emits_phase_changed_on_dawn_crossing() -> void:
	# Pin just before cycle wrap (still night at 7199), advance past wrap
	# (7201 % 7200 = 1, which is back into early day) and tick.
	var c = _make_clock(7199.0)
	var fired: Array = [false]
	var seen_is_day: Array = [false]
	c.phase_changed.connect(func(is_day: bool):
		fired[0] = true
		seen_is_day[0] = is_day)
	c._time_override = 7201.0
	c.tick(0.1)
	assert_bool(fired[0]).is_true()
	assert_bool(seen_is_day[0]).is_true()

# --- advance_to_phase: night → next dawn ---

func test_instance_advance_from_night_to_dawn_goes_forward() -> void:
	# Pinned to 5400 = midnight (phase 0.75). advance_to_phase(0.0) lands at next dawn.
	var c = _make_clock(5400.0)
	c.advance_to_phase(0.0)
	assert_float(c.phase_fraction()).is_equal_approx(0.0, 0.001)
	assert_bool(c.is_daytime()).is_true()

# --- moon_phase / day_count: explicit anchor cases ---

func test_instance_moon_phase_zero_at_unix_zero() -> void:
	var c = _make_clock(0.0)
	assert_int(c.moon_phase()).is_equal(0)

func test_instance_moon_phase_advances_one_per_cycle() -> void:
	var c = _make_clock(Constants.DAY_CYCLE_SECONDS)
	assert_int(c.moon_phase()).is_equal(1)

func test_instance_moon_fullness_zero_at_new_moon() -> void:
	var c = _make_clock(0.0)
	assert_float(c.moon_fullness()).is_equal_approx(0.0, 0.001)

func test_instance_moon_fullness_symmetric_around_full() -> void:
	# Phase 2 (waxing) and phase 6 (waning) should have equal fullness.
	var c2 = _make_clock(Constants.DAY_CYCLE_SECONDS * 2.0)
	var c6 = _make_clock(Constants.DAY_CYCLE_SECONDS * 6.0)
	assert_float(c2.moon_fullness()).is_equal_approx(c6.moon_fullness(), 0.001)
	assert_float(c2.moon_fullness()).is_equal_approx(0.5, 0.001)

func test_instance_day_count_zero_at_unix_zero() -> void:
	var c = _make_clock(0.0)
	assert_int(c.day_count()).is_equal(0)

func test_instance_day_count_advances_with_time() -> void:
	var c = _make_clock(Constants.DAY_CYCLE_SECONDS * 3.5)
	assert_int(c.day_count()).is_equal(3)
