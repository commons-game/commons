## Tests for the DayClock autoload — Phase 0c shim.
##
## Phase 0c of the per-island clock refactor: the DayClock autoload no longer
## owns its own DayClockInstance. It's a thin shim that delegates every call
## to `IslandRegistry.active_island().clock`. This file therefore covers the
## shim-delegation contract only:
##
##   - public methods forward to the active island's clock
##   - _time_override / _time_offset round-trip to the active clock
##   - phase_changed signal relays from the active clock
##   - switching the active island via IslandRegistry.set_active_island()
##     rebinds the relay so the *new* island's clock drives DayClock
##
## Timekeeping logic itself is covered by test_day_clock_instance.gd —
## those cases construct DayClockInstance directly so they don't depend on
## the global autoload singleton.
##
## These tests use the live IslandRegistry / DayClock autoloads, so each test
## restores `default` as the active island in its teardown to prevent
## cross-test pollution.
extends GdUnitTestSuite

const IslandScript := preload("res://world/Island.gd")
const IslandRegistryScript := preload("res://autoloads/IslandRegistry.gd")

# Test islands registered during a test, removed in after_test().
var _test_island_ids: Array[String] = []

func after_test() -> void:
	# Always restore default as active so the next test starts clean.
	IslandRegistry.set_active_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	for id in _test_island_ids:
		IslandRegistry.unregister_island(id)
	_test_island_ids.clear()
	# Also reset the default island's clock back to wall-clock-driven so
	# tests that don't use _time_override aren't poisoned by tests that did.
	var default_clock = IslandRegistry.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID).clock
	default_clock._time_override = -1.0
	default_clock._time_offset = 0.0
	default_clock.resync_phase()

func _make_test_island(id: String) -> RefCounted:
	var island = IslandScript.new(id)
	IslandRegistry.register_island(island)
	_test_island_ids.append(id)
	return island

# --- Constant re-export ---

func test_moon_phase_count_constant_still_accessible() -> void:
	# Several callers reference DayClock.MOON_PHASE_COUNT directly. The shim
	# must keep re-exporting it.
	assert_int(DayClock.MOON_PHASE_COUNT).is_equal(8)

# --- Method delegation: read paths ---

func test_is_daytime_delegates_to_active_clock() -> void:
	# Pin the default (active) island's clock to midday and verify the
	# autoload reflects it.
	var default_clock = IslandRegistry.active_island().clock
	default_clock._time_override = 1800.0  # midday
	assert_bool(DayClock.is_daytime()).is_true()
	default_clock._time_override = 5400.0  # midnight
	assert_bool(DayClock.is_daytime()).is_false()

func test_phase_fraction_delegates_to_active_clock() -> void:
	IslandRegistry.active_island().clock._time_override = 3600.0  # dusk
	assert_float(DayClock.phase_fraction()).is_equal_approx(0.5, 0.001)

func test_sky_alpha_delegates_to_active_clock() -> void:
	IslandRegistry.active_island().clock._time_override = 1800.0  # midday
	assert_float(DayClock.sky_alpha()).is_equal_approx(0.0, 0.01)

func test_moon_phase_and_fullness_delegate_to_active_clock() -> void:
	IslandRegistry.active_island().clock._time_override = Constants.DAY_CYCLE_SECONDS * 4.0
	assert_int(DayClock.moon_phase()).is_equal(4)
	assert_float(DayClock.moon_fullness()).is_equal_approx(1.0, 0.001)

# --- Property forwarding: _time_override / _time_offset round-trip ---

func test_time_override_setter_writes_to_active_clock() -> void:
	DayClock._time_override = 1234.5
	assert_float(IslandRegistry.active_island().clock._time_override).is_equal(1234.5)

func test_time_override_getter_reads_from_active_clock() -> void:
	IslandRegistry.active_island().clock._time_override = 4321.0
	assert_float(DayClock._time_override).is_equal(4321.0)

func test_time_offset_setter_writes_to_active_clock() -> void:
	DayClock._time_offset = 999.0
	assert_float(IslandRegistry.active_island().clock._time_offset).is_equal(999.0)

func test_time_offset_getter_reads_from_active_clock() -> void:
	IslandRegistry.active_island().clock._time_offset = 555.0
	assert_float(DayClock._time_offset).is_equal(555.0)

# --- Mutation methods delegate ---

func test_advance_to_phase_delegates_to_active_clock() -> void:
	# Pin to midday, advance to dawn — should wrap forward and the active
	# clock's phase should land on 0.
	IslandRegistry.active_island().clock._time_override = 1800.0
	DayClock.advance_to_phase(0.0)
	assert_float(IslandRegistry.active_island().clock.phase_fraction()).is_equal_approx(0.0, 0.001)

func test_set_start_phase_delegates_to_active_clock() -> void:
	IslandRegistry.active_island().clock._time_override = 1800.0
	DayClock.set_start_phase(0.5)
	assert_float(IslandRegistry.active_island().clock.phase_fraction()).is_equal_approx(0.5, 0.001)

# --- phase_changed signal relay ---

func test_phase_changed_signal_relays_from_active_clock() -> void:
	# Pin just-before-dusk, then advance and tick — DayClock.phase_changed
	# must fire because the *active* clock fired.
	var active_clock = IslandRegistry.active_island().clock
	active_clock._time_override = 3599.0
	active_clock.resync_phase()
	var fired: Array = [false]
	var seen_is_day: Array = [true]
	var cb := func(is_day: bool):
		fired[0] = true
		seen_is_day[0] = is_day
	DayClock.phase_changed.connect(cb)
	active_clock._time_override = 3601.0
	active_clock.tick(0.1)
	assert_bool(fired[0]).is_true()
	assert_bool(seen_is_day[0]).is_false()
	DayClock.phase_changed.disconnect(cb)

# --- Active-island switching ---

func test_switching_active_island_makes_dayclock_resolve_through_new_island() -> void:
	# Default island clock pinned to midday (daytime); test island pinned
	# to midnight (nighttime). Switching active island flips DayClock's
	# answer to is_daytime() without touching either clock.
	IslandRegistry.active_island().clock._time_override = 1800.0  # default = day
	assert_bool(DayClock.is_daytime()).is_true()

	var other = _make_test_island("test-shim-switch")
	other.clock._time_override = 5400.0  # other = night
	IslandRegistry.set_active_island("test-shim-switch")
	assert_bool(DayClock.is_daytime()).is_false()

func test_switching_active_island_relays_new_islands_phase_changed() -> void:
	# Bind to default island first, switch to a fresh test island, fire
	# its clock's phase_changed — DayClock.phase_changed must relay it.
	# Simultaneously the *old* island's signals must NOT relay anymore.
	var default_clock = IslandRegistry.active_island().clock
	default_clock._time_override = 1800.0  # daytime
	default_clock.resync_phase()

	var other = _make_test_island("test-shim-relay")
	other.clock._time_override = 3599.0  # just before dusk
	other.clock.resync_phase()

	IslandRegistry.set_active_island("test-shim-relay")

	var calls: Array = [0]
	var seen: Array = [true]
	var cb := func(is_day: bool):
		calls[0] += 1
		seen[0] = is_day
	DayClock.phase_changed.connect(cb)

	# Fire on the *new* (active) clock — should relay.
	other.clock._time_override = 3601.0
	other.clock.tick(0.1)
	assert_int(calls[0]).is_equal(1)
	assert_bool(seen[0]).is_false()

	# Fire on the *old* (now-inactive) clock — must NOT relay.
	default_clock._time_override = 3601.0
	default_clock.tick(0.1)
	assert_int(calls[0]).is_equal(1)  # still 1 — no extra relay

	DayClock.phase_changed.disconnect(cb)

func test_switching_active_island_resyncs_new_clock_to_avoid_spurious_emit() -> void:
	# When the active clock switches mid-night-to-mid-day, the new clock's
	# _last_is_day might be stale (it was seeded at construction with whatever
	# the wall clock said). The shim must call resync_phase() on the new
	# clock so the next tick() doesn't spuriously fire phase_changed.
	#
	# Simulate the failure mode: build an island whose clock is pinned to
	# night but whose _last_is_day is stuck at true (pretend it was seeded
	# while pinned to day). After switching, ticking the new active clock
	# with no actual phase change must NOT fire phase_changed.
	var other = _make_test_island("test-shim-resync")
	other.clock._time_override = 5400.0  # midnight
	other.clock._last_is_day = true       # stale (would otherwise fire on first tick)

	IslandRegistry.set_active_island("test-shim-resync")

	# If the shim called resync_phase() on bind, _last_is_day is now false.
	assert_bool(other.clock._last_is_day).is_false()

	var calls: Array = [0]
	var cb := func(_d): calls[0] += 1
	DayClock.phase_changed.connect(cb)
	other.clock.tick(0.1)
	assert_int(calls[0]).is_equal(0)
	DayClock.phase_changed.disconnect(cb)

# --- Phase 0d-i: accelerate_to / is_accelerating delegate through the shim ---

func test_accelerate_to_delegates_to_active_island_clock() -> void:
	# Two islands with their own clocks. Calling DayClock.accelerate_to()
	# must touch ONLY the active island's clock — the other island's clock
	# stays unchanged. This is the Phase 0d-ii contract: MergeCoordinator
	# will set the lagging island active just long enough to call
	# accelerate_to on it.
	var leader = _make_test_island("test-accel-leader")
	leader.clock._wall_time_override = 0.0
	# The default island is currently active; verify shim sees that clock.
	assert_bool(DayClock.is_accelerating()).is_false()
	# Switch active to the leader and accelerate it.
	IslandRegistry.set_active_island("test-accel-leader")
	DayClock.accelerate_to(0.5, 1.0)
	# The active (leader) clock now reports accelerating; the other does not.
	assert_bool(DayClock.is_accelerating()).is_true()
	assert_bool(leader.clock.is_accelerating()).is_true()
	var default_clock = IslandRegistry.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID).clock
	assert_bool(default_clock.is_accelerating()).is_false()
	# Switching active back to default flips DayClock.is_accelerating() too —
	# proves the shim is resolving at call time, not caching.
	IslandRegistry.set_active_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	assert_bool(DayClock.is_accelerating()).is_false()
