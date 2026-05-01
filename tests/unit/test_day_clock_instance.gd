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

# ---------------------------------------------------------------------------
# Phase 0d-i: accelerate_to() — clock acceleration primitive.
#
# `accelerate_to(target_total_phase, duration_seconds)` makes the clock run
# faster than wall time so that after `duration_seconds` real seconds, the
# clock's total phase (day_count + phase_fraction) equals
# `target_total_phase`. After the ramp the clock returns to wall-time pace
# but its `_time_offset` is permanently advanced (monotonic — no rewind).
#
# Implementation is driverless: the ramp resolves on every read via
# `_effective_offset()`. To make this testable without sleeping on the wall
# clock, the instance carries a `_wall_time_override` field — set it >= 0 to
# pin "now" for both the ramp and the wall-time-derived `_get_unix_time()`
# path. (Distinct from `_time_override`, which short-circuits the whole
# clock and is therefore incompatible with offset arithmetic.)
# ---------------------------------------------------------------------------

## Build a clock that uses the wall-time mock instead of `_time_override`.
## With `_wall_time_override` set, `_get_unix_time()` returns
## `_wall_time_override + _effective_offset()`, so we can simulate both wall
## time advancing and the acceleration ramp resolving against it.
func _make_wall_clock(wall_time: float):
	var c = DayClockInstanceScript.new()
	c._wall_time_override = wall_time
	c.resync_phase()
	return c

# --- baseline plumbing ---

func test_instance_wall_time_override_drives_unix_time() -> void:
	# Sanity: with _wall_time_override set, _get_unix_time() reflects it.
	var c = _make_wall_clock(1800.0)
	assert_float(c._get_unix_time()).is_equal_approx(1800.0, 0.001)
	assert_float(c.phase_fraction()).is_equal_approx(0.25, 0.001)

func test_instance_is_accelerating_false_by_default() -> void:
	var c = _make_wall_clock(0.0)
	assert_bool(c.is_accelerating()).is_false()

# --- accelerate_to: the ramp lands at the target ---

func test_accelerate_to_advances_phase_at_target_time() -> void:
	# Start at unix 0 (phase 0.0, day 0). Ask the clock to advance to
	# total_phase = 0.5 (i.e. dusk of day 0) over 1.0 seconds of wall time.
	# After 1.0 wall seconds elapse, phase_fraction() must be ~0.5.
	var c = _make_wall_clock(0.0)
	c.accelerate_to(0.5, 1.0)
	# Halfway through the ramp the helper is_accelerating() should still be true.
	assert_bool(c.is_accelerating()).is_true()
	# Advance wall time to the end of the ramp.
	c._wall_time_override = 1.0
	assert_float(c.phase_fraction()).is_equal_approx(0.5, 0.001)
	# After the ramp commits, is_accelerating() flips to false.
	assert_bool(c.is_accelerating()).is_false()

func test_accelerate_to_partial_at_halfway() -> void:
	# Linear ramp: at 50% of duration we should have applied 50% of the
	# extra offset, i.e. phase 0.0 -> target 0.5 -> halfway = 0.25.
	var c = _make_wall_clock(0.0)
	c.accelerate_to(0.5, 1.0)
	c._wall_time_override = 0.5
	assert_float(c.phase_fraction()).is_equal_approx(0.25, 0.001)
	# Ramp is still active (haven't crossed the duration boundary yet).
	assert_bool(c.is_accelerating()).is_true()

func test_accelerate_to_commits_offset_after_duration() -> void:
	# After the ramp ends, the extra offset must be permanently committed to
	# `_time_offset` so subsequent reads don't depend on `_accel_*` state.
	var c = _make_wall_clock(0.0)
	c.accelerate_to(0.5, 1.0)
	# Advance past the end of the ramp, triggering the commit on read.
	c._wall_time_override = 1.5
	var phase_at_15 := c.phase_fraction()
	# 1.5 wall seconds + committed offset of (0.5 cycles = 3600s) = 3601.5
	# unix; phase_fraction = (3601.5 mod 7200) / 7200 = 0.50020833...
	assert_float(phase_at_15).is_equal_approx(0.5002, 0.001)
	# After commit: is_accelerating() is false and `_time_offset` carries
	# the full extra offset (3600 seconds = 0.5 of a cycle).
	assert_bool(c.is_accelerating()).is_false()
	assert_float(c._time_offset).is_equal_approx(3600.0, 0.001)
	# Advance wall time further; the clock should track wall time 1:1 again
	# (no extra ramp contribution beyond the committed offset).
	c._wall_time_override = 1000.0
	# unix = 1000 + 3600 = 4600; phase = 4600/7200 ≈ 0.6388...
	assert_float(c.phase_fraction()).is_equal_approx(4600.0 / 7200.0, 0.001)

func test_accelerate_to_target_in_past_is_noop() -> void:
	# A target phase that's <= the current phase must not rewind the clock.
	# Phase 0d use-case: the *leading* clock should never accelerate to match
	# a *lagging* clock (only the lagging side accelerates forward).
	var c = _make_wall_clock(3600.0)  # phase 0.5 (dusk), day 0
	# Current total_phase = 0 + 0.5 = 0.5. Asking for 0.25 (in the past) is a no-op.
	c.accelerate_to(0.25, 1.0)
	assert_bool(c.is_accelerating()).is_false()
	assert_float(c._time_offset).is_equal_approx(0.0, 0.001)
	# Asking for exactly the current total_phase is also a no-op.
	c.accelerate_to(0.5, 1.0)
	assert_bool(c.is_accelerating()).is_false()
	assert_float(c._time_offset).is_equal_approx(0.0, 0.001)

func test_accelerate_to_does_not_break_advance_to_phase() -> void:
	# advance_to_phase must remain monotonic-forward both during and after a
	# ramp. After the ramp commits, calling advance_to_phase should still
	# only ever move forward.
	var c = _make_wall_clock(0.0)
	c.accelerate_to(0.5, 1.0)
	c._wall_time_override = 1.0  # ramp completes on next read
	var phase_after_ramp := c.phase_fraction()
	assert_float(phase_after_ramp).is_equal_approx(0.5, 0.001)
	# Now ask advance_to_phase to land at 0.75 — should advance forward.
	c.advance_to_phase(0.75)
	assert_float(c.phase_fraction()).is_equal_approx(0.75, 0.001)
	# And asking for 0.0 should wrap forward to the next dawn, never rewind.
	var unix_before: float = c._get_unix_time()
	c.advance_to_phase(0.0)
	var unix_after: float = c._get_unix_time()
	assert_float(unix_after).is_greater(unix_before)
	assert_float(c.phase_fraction()).is_equal_approx(0.0, 0.001)

func test_accelerate_to_crosses_multi_day_target() -> void:
	# Target several days in the future to confirm the math handles
	# total_phase > 1.0 cleanly (not just intra-day fractions).
	var c = _make_wall_clock(0.0)
	# Start: day 0, phase 0.0 → total_phase 0.0.
	# Target: total_phase 2.5 (day 2, midnight) over 2.0 wall seconds.
	c.accelerate_to(2.5, 2.0)
	c._wall_time_override = 2.0
	# After commit: unix_time = 2.0 + (2.5 * 7200) = 18002.0
	assert_int(c.day_count()).is_equal(2)
	assert_float(c.phase_fraction()).is_equal_approx(0.5, 0.001)

# --- phase_changed during acceleration ---
#
# DayClockInstance is driverless: phase_changed only emits when somebody
# calls tick(). So the *exact wall-time* boundary crossing isn't observable.
# What we *can* guarantee: if the ramp crosses the day/night boundary and
# tick() is called after the ramp commits, phase_changed fires reflecting
# the post-ramp phase. The signal does NOT fire mid-ramp without a tick().
#
# This is the documented limitation: phase_changed-during-acceleration
# requires polling. Phase 0d-ii can wire MergeCoordinator to tick the
# accelerating clock if continuous boundary observation matters.

func test_phase_changed_fires_after_ramp_crosses_boundary() -> void:
	# Start at midday (phase 0.25, daytime), accelerate to past dusk.
	# After the ramp, tick() must observe the day→night transition.
	var c = _make_wall_clock(1800.0)  # phase 0.25, daytime
	var fired: Array = [false]
	var seen_is_day: Array = [true]
	c.phase_changed.connect(func(is_day: bool):
		fired[0] = true
		seen_is_day[0] = is_day)
	c.accelerate_to(0.6, 1.0)  # cross dusk into night
	# Advance wall time past the ramp end.
	c._wall_time_override = 1801.0
	c.tick(0.1)
	assert_bool(fired[0]).is_true()
	assert_bool(seen_is_day[0]).is_false()

# --- multi-instance independence ---

func test_accelerate_to_does_not_affect_other_instances() -> void:
	# The whole point of per-island clocks: accelerating one must not touch
	# another. This is the Phase 0d use-case in miniature.
	var a = _make_wall_clock(0.0)
	var b = _make_wall_clock(0.0)
	a.accelerate_to(0.5, 1.0)
	a._wall_time_override = 1.0
	# Force a's ramp to commit by reading its phase.
	var _drain = a.phase_fraction()
	# b is unchanged.
	assert_float(b._time_offset).is_equal_approx(0.0, 0.001)
	assert_bool(b.is_accelerating()).is_false()
