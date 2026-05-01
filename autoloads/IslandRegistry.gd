## IslandRegistry — singleton tracking all islands in the current session.
##
## Phase 0b of the per-island clock refactor: the registry creates one default
## implicit island at startup, used by solo / pre-merge state.
##
## Phase 0c wired DayClock to resolve through this registry (autoload became a
## thin shim: DayClock.is_daytime() -> active_island().clock.is_daytime()).
##
## Phase 0d-ii: this registry now orchestrates the full island lifecycle on
## merge / split. begin_merge() starts a clock-convergence transition (the
## lagging clock accelerates toward the leader); tick_merge() drives the
## accelerating clock so phase_changed fires for boundary crossings mid-ramp;
## once both sides are caught up, _complete_merge() creates the deterministic
## merged island and swaps it active. split_from_merge() creates a fresh
## island for the leaver, preserving its current clock state (monotonic — no
## rewind of in-game time).
extends Node

const IslandScript := preload("res://world/Island.gd")
const DayClockInstanceScript := preload("res://world/DayClockInstance.gd")
const DEFAULT_ISLAND_ID := "default"

## Phase 0c: emitted whenever the active island reference changes. The
## DayClock shim listens to this so it can rebind its phase_changed relay
## to the newly-active island's clock. Phase 0d (MergeCoordinator wiring)
## will be the first place this actually fires in production.
signal active_island_changed(island)

var _islands: Dictionary = {}  # id (String) -> Island (RefCounted)
var _default_island: RefCounted
## Phase 0c: which island the local session currently inhabits. Single-island
## in 0c (always DEFAULT_ISLAND_ID); Phase 0d wires merge/split events to
## flip this and emit active_island_changed.
var _active_island_id: String = DEFAULT_ISLAND_ID

func _ready() -> void:
	_default_island = IslandScript.new(DEFAULT_ISLAND_ID)
	_islands[DEFAULT_ISLAND_ID] = _default_island

## Phase 0b: ignores the argument and always returns the default island.
## Phase 0c will resolve via the player's actual island membership; the
## argument is left untyped here because the eventual call shape (Player,
## session_id String, peer int?) is not yet decided — typing it now would
## just force a churn edit in 0c.
func island_for(_player_or_session_id) -> RefCounted:
	return _default_island

func get_island(island_id: String) -> RefCounted:
	return _islands.get(island_id, null)

func all_islands() -> Array:
	return _islands.values()

## Phase 0d will use this when a split spawns a new island.
func register_island(island: RefCounted) -> void:
	_islands[island.id] = island

## Phase 0d will use this when an island merges into another and dissolves.
## The default island cannot be unregistered — it must persist for the whole
## session so island_for() always has something to return.
func unregister_island(island_id: String) -> void:
	if island_id != DEFAULT_ISLAND_ID:
		_islands.erase(island_id)

## Phase 0c: the island the local session is currently part of. The DayClock
## shim resolves through this instead of holding its own DayClockInstance —
## so flipping the active island flips which clock DayClock.is_daytime() etc.
## answer from. Falls back to the default island if the active id has been
## unregistered out from under us (defensive — shouldn't happen, but a null
## active island would brick every DayClock callsite).
func active_island() -> RefCounted:
	return _islands.get(_active_island_id, _default_island)

## Phase 0c: switch the active island. No-op if the id is already active or
## unknown — both branches deliberately suppress active_island_changed:
##   - same id: avoids spurious signal-rebinds in the DayClock shim during
##     defensive set_active_island() calls that 0d's MergeCoordinator may
##     emit on every merge step.
##   - unknown id: keeping the previous active island is safer than nulling
##     it out (which would brick the shim), and a stale id is a caller bug
##     we'd rather log loudly than silently honour.
func set_active_island(island_id: String) -> void:
	if _active_island_id == island_id:
		return
	if not _islands.has(island_id):
		push_error("IslandRegistry.set_active_island: unknown island '%s'" % island_id)
		return
	_active_island_id = island_id
	active_island_changed.emit(active_island())

# ---------------------------------------------------------------------------
# Phase 0d-ii: merge / split lifecycle
# ---------------------------------------------------------------------------
#
# The merge path runs on each peer independently and converges:
#
#   begin_merge(remote_total_phase, transition_seconds, merged_island_id)
#     ↳ if local is lagging:  active clock.accelerate_to(remote, transition_seconds)
#     ↳ if local is leading:  no acceleration; just wait wall time
#     ↳ remembers (target, merged_island_id) so tick_merge can detect completion
#
#   tick_merge(delta) — called every frame while is_merging() is true
#     ↳ ticks the active clock so phase_changed fires on day/night boundaries
#       crossed mid-ramp (DayClockInstance is driverless; ramps only commit
#       on read, so without this nothing would fire boundary signals)
#     ↳ when the clock has caught up to the target AND is no longer
#       accelerating, calls _complete_merge()
#
#   _complete_merge()
#     ↳ creates the merged Island (idempotent — register_island reuses if
#       the id is taken) and seeds its clock to the converged total_phase
#       from the local active clock (both peers compute the same target →
#       both merged clocks land at the same phase)
#     ↳ retires the old solo island (skipped if the old island was default,
#       since default cannot be unregistered)
#     ↳ swaps active_island → the merged id
#
# Pairwise-only: the brief notes the current MergeCoordinator handles exactly
# 2 peers per merge. begin_merge takes a single remote phase. Future N-way
# generalisation would take an Array; we keep the scalar shape today to
# avoid speculative API surface.

## Active merge transition state. _merge_target_total_phase < 0 means no merge
## in progress. _merge_pre_island_id is the island we were on before the merge
## began (so _complete_merge knows what to retire).
var _merge_target_total_phase: float = -1.0
var _merge_island_id: String = ""
var _merge_pre_island_id: String = ""

## Begin a merge transition on this peer. Both peers should call this with
## the same transition_seconds and merged_island_id (computed deterministically
## by MergeCoordinator from the sorted session ids).
##
## Returns true if a transition was started, false on no-op (e.g. the local
## clock is already at or past the remote phase, AND we're already on the
## merged island, so there's nothing to do).
##
## Implementation notes:
##   - The "lagging" peer accelerates its clock toward remote_total_phase.
##   - The "leading" peer doesn't call accelerate_to (per the brief: cleaner
##     than relying on accelerate_to's at-or-behind-target push_error path).
##   - We store the convergence target so tick_merge can detect "both sides
##     have caught up" by comparing the clock's current total_phase.
func begin_merge(remote_total_phase: float, transition_seconds: float, merged_island_id: String) -> bool:
	var clock = active_island().clock
	var local_total_phase: float = float(clock.day_count()) + clock.phase_fraction()
	# The convergence target is whichever peer is ahead. Both peers compute
	# the same max independently → both end up at the same total phase.
	var target: float = maxf(local_total_phase, remote_total_phase)
	# No-op if there's nothing to converge to AND we're already on the merged
	# island. Without the second clause, two perfectly-synced peers would skip
	# the swap entirely and stay on their solo islands.
	if target <= local_total_phase and _active_island_id == merged_island_id:
		return false
	_merge_target_total_phase = target
	_merge_island_id = merged_island_id
	_merge_pre_island_id = _active_island_id
	# Lagging side ramps; leading side just waits wall time. The strict
	# inequality avoids accelerate_to's push_error on at-or-behind targets.
	if local_total_phase < target:
		clock.accelerate_to(target, transition_seconds)
	return true

## True while a merge transition is running on this peer.
func is_merging() -> bool:
	return _merge_target_total_phase >= 0.0

## Tick the merge transition. Drives the active clock's tick() so phase_changed
## fires on day/night boundaries the ramp crosses mid-transition. Auto-completes
## the merge once the clock has caught up to the target AND the ramp (if any)
## has committed. Caller (MergeCoordinator) should invoke this every _process
## while is_merging() returns true.
func tick_merge(delta: float) -> void:
	if not is_merging():
		return
	var clock = active_island().clock
	# Drive the clock forward so any boundary crossings during the ramp emit
	# phase_changed. Without this, DayClockInstance's read-side ramp commit
	# would happen silently and consumers (NightDarkness / NightSpawner) would
	# only see the post-merge phase via the synthetic emit on swap.
	clock.tick(delta)
	# Completion gate: the clock must have caught up to the target AND must
	# no longer be accelerating. is_accelerating() goes false on the read that
	# crosses the ramp end (driverless commit), and the tick() above is one
	# such read.
	var current_total_phase: float = float(clock.day_count()) + clock.phase_fraction()
	if current_total_phase + 0.0001 >= _merge_target_total_phase and not clock.is_accelerating():
		_complete_merge()

## Create the merged island (if absent) and swap to it. Idempotent — calling
## twice with no intervening begin_merge() is a no-op (is_merging() is false
## after the first call so the second short-circuits via the guard).
##
## Public for tests; production calls happen automatically from tick_merge().
func _complete_merge() -> void:
	if not is_merging():
		return
	var merged_id := _merge_island_id
	var pre_id := _merge_pre_island_id
	var clock = active_island().clock
	var converged_total_phase: float = float(clock.day_count()) + clock.phase_fraction()
	# Reset transition state BEFORE the swap so any signal handlers triggered
	# by set_active_island() see is_merging() == false.
	_merge_target_total_phase = -1.0
	_merge_island_id = ""
	_merge_pre_island_id = ""
	# Create the merged island if it doesn't exist yet. Both peers do this
	# independently with the same id; whoever calls first wins, the other's
	# call is a register_island overwrite — but the seeded clock values are
	# computed from the same converged target on both peers, so the resulting
	# clocks are observationally identical.
	var merged_island = _islands.get(merged_id, null)
	if merged_island == null:
		merged_island = IslandScript.new(merged_id)
		register_island(merged_island)
	# Seed the merged island's clock to the converged total phase. We do this
	# by setting _time_offset so that wall_time + offset == target_unix_time.
	# (The merged clock is freshly constructed so it has no _time_override or
	# active ramp to fight.)
	var target_unix: float = converged_total_phase * float(Constants.DAY_CYCLE_SECONDS)
	var wall_now: float = Time.get_unix_time_from_system()
	merged_island.clock._time_offset = target_unix - wall_now
	merged_island.clock.resync_phase()
	set_active_island(merged_id)
	# Retire the pre-merge island unless it was the default (default cannot
	# be unregistered — see unregister_island). The default island is reused
	# on split.
	if pre_id != DEFAULT_ISLAND_ID and pre_id != merged_id:
		unregister_island(pre_id)

## Split: the local peer just lost its merge partner. Create a fresh island
## seeded from the current (merged) clock state — preserving in-game time
## monotonically, no rewind — and swap to it.
##
## new_island_id is computed by the caller (MergeCoordinator) from the local
## session id so it's stable across reconnects but not collidable with another
## peer's solo island.
func split_from_merge(new_island_id: String) -> void:
	var current_clock = active_island().clock
	var current_total_phase: float = float(current_clock.day_count()) + current_clock.phase_fraction()
	# If the new island already exists (e.g. a previous split made it), reuse
	# it but reseat its clock to the current converged phase — never rewind.
	var new_island = _islands.get(new_island_id, null)
	if new_island == null:
		new_island = IslandScript.new(new_island_id)
		register_island(new_island)
	var target_unix: float = current_total_phase * float(Constants.DAY_CYCLE_SECONDS)
	var wall_now: float = Time.get_unix_time_from_system()
	new_island.clock._time_offset = target_unix - wall_now
	new_island.clock.resync_phase()
	# Retire the merged island we were on (if it wasn't default and isn't the
	# new id). The other peer will do the same when their split fires.
	var pre_id := _active_island_id
	set_active_island(new_island_id)
	if pre_id != DEFAULT_ISLAND_ID and pre_id != new_island_id:
		unregister_island(pre_id)
