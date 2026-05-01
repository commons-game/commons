## Tests for IslandRegistry — the autoload tracking all islands in a session.
##
## Phase 0b: registry creates one default implicit island at startup; for now
## island_for() always returns it (Phase 0c will resolve via the player's
## actual island membership, Phase 0d will create/merge/destroy islands in
## response to MergeCoordinator events).
##
## These tests construct the registry directly via `.new()` rather than
## relying on the autoload singleton, so they can pin behaviour without
## depending on global state. (The autoload entry is verified by the fact
## that the project still compiles and runs.)
extends GdUnitTestSuite

const IslandRegistryScript := preload("res://autoloads/IslandRegistry.gd")
const IslandScript := preload("res://world/Island.gd")

func _make_registry():
	# IslandRegistry extends Node. _ready() seeds the default island, but
	# _ready() doesn't fire until the node enters the scene tree, so add it
	# under the test suite (auto_free disposes it at the end of the test).
	var r = auto_free(IslandRegistryScript.new())
	add_child(r)
	return r

# --- Default island bootstrap ---

func test_default_island_exists_after_init() -> void:
	var r = _make_registry()
	var island = r.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	assert_object(island).is_not_null()
	assert_str(island.id).is_equal(IslandRegistryScript.DEFAULT_ISLAND_ID)

func test_default_island_owns_a_clock() -> void:
	var r = _make_registry()
	var island = r.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	assert_object(island.clock).is_not_null()
	assert_bool(island.clock.has_method("is_daytime")).is_true()

func test_all_islands_includes_default_after_init() -> void:
	var r = _make_registry()
	var islands = r.all_islands()
	assert_int(islands.size()).is_equal(1)

# --- island_for() — Phase 0b: ignore arg, always return default ---

func test_island_for_returns_default_for_any_arg() -> void:
	var r = _make_registry()
	var default_island = r.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	# The arg is intentionally untyped/ignored in Phase 0b; verify across a
	# few representative shapes.
	assert_object(r.island_for("any-session-id")).is_same(default_island)
	assert_object(r.island_for(null)).is_same(default_island)
	assert_object(r.island_for(42)).is_same(default_island)

# --- register_island / unregister_island ---

func test_register_island_adds_to_registry() -> void:
	var r = _make_registry()
	var extra = IslandScript.new("extra")
	r.register_island(extra)
	assert_object(r.get_island("extra")).is_same(extra)
	assert_int(r.all_islands().size()).is_equal(2)

func test_unregister_island_removes_non_default() -> void:
	var r = _make_registry()
	var extra = IslandScript.new("extra")
	r.register_island(extra)
	r.unregister_island("extra")
	assert_object(r.get_island("extra")).is_null()
	assert_int(r.all_islands().size()).is_equal(1)

func test_unregister_default_island_is_a_noop() -> void:
	# The default island must persist for the whole session; removing it
	# would leave island_for() returning null and break every caller.
	var r = _make_registry()
	r.unregister_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	var island = r.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	assert_object(island).is_not_null()
	assert_int(r.all_islands().size()).is_equal(1)

# --- get_island ---

func test_get_island_returns_null_for_unknown_id() -> void:
	var r = _make_registry()
	assert_object(r.get_island("nonexistent")).is_null()

# --- active island (Phase 0c) ---
#
# Phase 0c lets the registry track which island is "active" — the one the
# DayClock shim resolves through. Phase 0c is still single-island (the
# default island is always active), but the API needs to exist so 0d can
# wire MergeCoordinator to switch active island during merge transitions.

func test_active_island_defaults_to_default() -> void:
	var r = _make_registry()
	var default_island = r.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	assert_object(r.active_island()).is_same(default_island)

func test_set_active_island_switches_active() -> void:
	var r = _make_registry()
	var extra = IslandScript.new("extra")
	r.register_island(extra)
	r.set_active_island("extra")
	assert_object(r.active_island()).is_same(extra)

func test_set_active_island_emits_active_island_changed() -> void:
	var r = _make_registry()
	var extra = IslandScript.new("extra")
	r.register_island(extra)
	var fired: Array = [false]
	var emitted_island: Array = [null]
	r.active_island_changed.connect(func(island):
		fired[0] = true
		emitted_island[0] = island)
	r.set_active_island("extra")
	assert_bool(fired[0]).is_true()
	assert_object(emitted_island[0]).is_same(extra)

func test_set_active_island_to_same_id_is_a_noop() -> void:
	# Switching to the already-active island must not re-emit — Phase 0d's
	# MergeCoordinator will likely call set_active_island() defensively on
	# every merge step and we don't want spurious clock-rebinds.
	var r = _make_registry()
	var calls: Array = [0]
	r.active_island_changed.connect(func(_island): calls[0] += 1)
	r.set_active_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	assert_int(calls[0]).is_equal(0)

func test_set_active_island_unknown_id_is_a_noop() -> void:
	# Defensive: if a stale island id is passed, keep the previous active
	# island rather than silently nulling out the active reference.
	var r = _make_registry()
	var default_island = r.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	r.set_active_island("nonexistent")
	assert_object(r.active_island()).is_same(default_island)

# --- Phase 0d-ii: merge / split lifecycle ---
#
# These tests exercise the orchestration that wires DayClockInstance.accelerate_to
# into the active-island swap. They construct a fresh registry, pin the default
# island's clock to a known phase via _wall_time_override, then drive
# begin_merge / tick_merge / split_from_merge directly.
#
# The clock arithmetic uses _wall_time_override exclusively so the ramp's
# elapsed-time calculation is deterministic — the test owns the wall clock.

const MERGED_ID := "merge:peerA:peerB"

func _pin_default_clock(r, wall_time: float, phase_offset_seconds: float = 0.0) -> RefCounted:
	# Pin the default island's clock to a known wall time and offset. The
	# resulting total_phase is (wall + offset) / DAY_CYCLE_SECONDS.
	var clock = r.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID).clock
	clock._wall_time_override = wall_time
	clock._time_offset = phase_offset_seconds
	clock.resync_phase()
	return clock

func test_begin_merge_with_lagging_local_phase_accelerates() -> void:
	# Local clock at total_phase 0.3 (mid-day), remote at 0.7 (mid-night).
	# begin_merge should ramp the local clock up to the remote phase.
	var r = _make_registry()
	var clock = _pin_default_clock(r, 0.3 * Constants.DAY_CYCLE_SECONDS)
	var started: bool = r.begin_merge(0.7, 1.0, MERGED_ID)
	assert_bool(started).is_true()
	assert_bool(r.is_merging()).is_true()
	assert_bool(clock.is_accelerating()).is_true()

func test_begin_merge_with_leading_local_phase_no_accel() -> void:
	# Local at 0.7, remote at 0.3 → local is leading; clock must NOT
	# accelerate (accelerate_to would push_error on at-or-behind targets).
	# is_merging() is still true so tick_merge can wait wall time.
	var r = _make_registry()
	var clock = _pin_default_clock(r, 0.7 * Constants.DAY_CYCLE_SECONDS)
	var started: bool = r.begin_merge(0.3, 1.0, MERGED_ID)
	assert_bool(started).is_true()
	assert_bool(r.is_merging()).is_true()
	assert_bool(clock.is_accelerating()).is_false()

func test_begin_merge_synced_peers_already_on_merged_island_is_noop() -> void:
	# If the local clock is at the target AND we're already on the merged
	# island, begin_merge has nothing to do.
	var r = _make_registry()
	var merged = IslandScript.new(MERGED_ID)
	r.register_island(merged)
	r.set_active_island(MERGED_ID)
	# Pin the merged clock to the target phase exactly.
	merged.clock._wall_time_override = 0.5 * Constants.DAY_CYCLE_SECONDS
	merged.clock._time_offset = 0.0
	merged.clock.resync_phase()
	var started: bool = r.begin_merge(0.5, 1.0, MERGED_ID)
	assert_bool(started).is_false()
	assert_bool(r.is_merging()).is_false()

func test_tick_merge_advances_accelerating_clock() -> void:
	# Drive tick_merge with delta and an advancing wall clock; the lagging
	# clock should advance and eventually catch up.
	var r = _make_registry()
	var clock = _pin_default_clock(r, 0.0)
	r.begin_merge(0.5, 1.0, MERGED_ID)
	assert_bool(clock.is_accelerating()).is_true()
	# Halfway through wall time → halfway through ramp → phase ~0.25
	clock._wall_time_override = 0.5
	r.tick_merge(0.5)
	assert_float(clock.phase_fraction()).is_equal_approx(0.25, 0.01)
	# Still merging (haven't crossed the duration boundary)
	assert_bool(r.is_merging()).is_true()

func test_tick_merge_completes_when_clock_catches_up() -> void:
	# Past the ramp end, tick_merge should detect convergence and complete.
	var r = _make_registry()
	var clock = _pin_default_clock(r, 0.0)
	r.begin_merge(0.5, 1.0, MERGED_ID)
	clock._wall_time_override = 1.5  # past ramp end
	r.tick_merge(0.1)
	assert_bool(r.is_merging()).is_false()
	# Active island should now be the merged one.
	assert_str(r.active_island().id).is_equal(MERGED_ID)

func test_complete_merge_swaps_to_merged_island() -> void:
	# After convergence the merged island is registered, active, and the
	# pre-merge default island is preserved (default cannot be retired).
	var r = _make_registry()
	var clock = _pin_default_clock(r, 0.0)
	r.begin_merge(0.5, 1.0, MERGED_ID)
	clock._wall_time_override = 1.5
	r.tick_merge(0.1)
	var merged = r.get_island(MERGED_ID)
	assert_object(merged).is_not_null()
	assert_object(r.active_island()).is_same(merged)
	# Default island must still exist (it's never retired).
	assert_object(r.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID)).is_not_null()

func test_complete_merge_retires_non_default_pre_island() -> void:
	# When the pre-merge island is non-default (e.g. a previous solo: island
	# from a prior split), it should be unregistered after the swap.
	var r = _make_registry()
	var solo = IslandScript.new("solo:peerA")
	# Seed the solo clock so begin_merge will accelerate it.
	solo.clock._wall_time_override = 0.0
	solo.clock._time_offset = 0.0
	solo.clock.resync_phase()
	r.register_island(solo)
	r.set_active_island("solo:peerA")
	r.begin_merge(0.5, 1.0, MERGED_ID)
	solo.clock._wall_time_override = 1.5
	r.tick_merge(0.1)
	# Pre-merge island retired.
	assert_object(r.get_island("solo:peerA")).is_null()
	# Merged island active.
	assert_str(r.active_island().id).is_equal(MERGED_ID)

func test_complete_merge_seeds_clock_to_converged_phase() -> void:
	# The merged clock must read the converged total_phase. Both peers will
	# compute the same target → both merged clocks will be at the same phase.
	var r = _make_registry()
	var clock = _pin_default_clock(r, 0.0)
	r.begin_merge(0.5, 1.0, MERGED_ID)
	clock._wall_time_override = 1.5
	r.tick_merge(0.1)
	var merged = r.get_island(MERGED_ID)
	assert_float(merged.clock.phase_fraction()).is_equal_approx(0.5, 0.01)

func test_complete_merge_idempotent() -> void:
	# Calling _complete_merge twice (or once, then again with no intervening
	# begin_merge) must not crash or double-swap.
	var r = _make_registry()
	var clock = _pin_default_clock(r, 0.0)
	r.begin_merge(0.5, 1.0, MERGED_ID)
	clock._wall_time_override = 1.5
	r.tick_merge(0.1)  # completes
	r._complete_merge()  # second call — guard makes it a no-op
	assert_bool(r.is_merging()).is_false()
	assert_str(r.active_island().id).is_equal(MERGED_ID)

# --- Split ---

func test_split_from_merge_creates_new_island_active() -> void:
	# Start on a merged island, call split_from_merge → new island exists
	# and is active.
	var r = _make_registry()
	var merged = IslandScript.new(MERGED_ID)
	r.register_island(merged)
	r.set_active_island(MERGED_ID)
	r.split_from_merge("solo:peerA")
	var fresh = r.get_island("solo:peerA")
	assert_object(fresh).is_not_null()
	assert_object(r.active_island()).is_same(fresh)

func test_split_from_merge_preserves_clock_state() -> void:
	# The fresh island's clock must read the same phase the merged clock had
	# at the moment of split — no rewind, monotonic forward only.
	var r = _make_registry()
	var merged = IslandScript.new(MERGED_ID)
	merged.clock._wall_time_override = 0.5 * Constants.DAY_CYCLE_SECONDS
	merged.clock._time_offset = 0.0
	merged.clock.resync_phase()
	r.register_island(merged)
	r.set_active_island(MERGED_ID)
	var phase_before: float = merged.clock.phase_fraction()
	r.split_from_merge("solo:peerA")
	var fresh = r.get_island("solo:peerA")
	assert_float(fresh.clock.phase_fraction()).is_equal_approx(phase_before, 0.01)

func test_split_from_merge_retires_old_merged_island() -> void:
	# After split, the merged island we were on should be unregistered (only
	# the default and the fresh solo island remain).
	var r = _make_registry()
	var merged = IslandScript.new(MERGED_ID)
	r.register_island(merged)
	r.set_active_island(MERGED_ID)
	r.split_from_merge("solo:peerA")
	assert_object(r.get_island(MERGED_ID)).is_null()
