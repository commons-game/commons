## DayClock — autoload. Phase 0c shim that resolves through IslandRegistry.
##
## Phase 0c of the per-island clock refactor: this autoload no longer owns
## a DayClockInstance. Every public method, the phase_changed signal, and
## the _time_override / _time_offset properties forward to whichever
## DayClockInstance the currently-active island owns
## (`IslandRegistry.active_island().clock`).
##
## Single-island in 0c: only the default island exists and it's always
## active, so behaviour is identical to Phase 0a/0b from a caller's
## perspective. Phase 0d wires MergeCoordinator merge/split events to flip
## the active island, at which point the signal-rebind logic below starts
## firing in production.
##
## Cycle: Constants.DAY_CYCLE_SECONDS (default 7200 = 60 min day + 60 min night)
##   Phase 0.00–0.50 = daytime  (phase_fraction 0 = dawn, 0.25 = midday)
##   Phase 0.50–1.00 = nighttime (0.50 = dusk, 0.75 = midnight)
##
## Testability: set DayClock._time_override >= 0 to pin the active clock to
## a fixed unix time. (Forwards to the active island's clock.)
##
## NOTE on autoload order: this shim depends on IslandRegistry being _ready
## *before* this script's _ready runs (we read `IslandRegistry.active_island()`
## there). Project.godot lists IslandRegistry first for that reason.
extends Node

const DayClockInstanceScript := preload("res://world/DayClockInstance.gd")

## Re-exported so existing callers reading `DayClock.MOON_PHASE_COUNT` keep working.
const MOON_PHASE_COUNT := DayClockInstanceScript.MOON_PHASE_COUNT

## Emitted when the active clock crosses the day/night boundary. Relayed
## from whichever DayClockInstance the active island owns; the connection
## rebinds when IslandRegistry.active_island_changed fires.
signal phase_changed(is_day: bool)

## The clock we're currently relaying phase_changed from. Tracked so we can
## disconnect cleanly when the active island switches. Held as RefCounted
## (matching the rest of the codebase — DayClockInstance is intentionally
## not registered as a globally-typed class).
var _bound_clock: RefCounted = null

# --- Forwarded mutable state ---
#
# World.gd dev hooks and tests write/read DayClock._time_override and
# _time_offset directly. Property accessors round-trip them to whichever
# clock is currently active. Phase 0a's wrapper used the same pattern; the
# only change in 0c is that the underlying field lives on the active
# island's clock instead of a wrapper-local _instance.

var _time_override: float:
	get:
		return IslandRegistry.active_island().clock._time_override
	set(value):
		IslandRegistry.active_island().clock._time_override = value

var _time_offset: float:
	get:
		return IslandRegistry.active_island().clock._time_offset
	set(value):
		IslandRegistry.active_island().clock._time_offset = value

func _ready() -> void:
	# Bind to the active clock's phase_changed and re-bind whenever the
	# active island changes. The bind also calls resync_phase() on the new
	# clock so a stale _last_is_day (e.g. seeded under a different pinned
	# time) doesn't fire a spurious phase_changed on the next tick.
	_bind_to_active_clock()
	IslandRegistry.active_island_changed.connect(_on_active_island_changed)

## Subscribe to the active island's clock.phase_changed signal, dropping any
## previous subscription first. Also resync the new clock's _last_is_day so
## the next tick doesn't spuriously emit — same legacy semantic Phase 0a's
## wrapper preserved by calling resync_phase() in its own _ready().
func _bind_to_active_clock() -> void:
	var new_clock: RefCounted = IslandRegistry.active_island().clock
	if _bound_clock == new_clock:
		return
	if _bound_clock != null and _bound_clock.phase_changed.is_connected(_relay_phase_changed):
		_bound_clock.phase_changed.disconnect(_relay_phase_changed)
	_bound_clock = new_clock
	if not _bound_clock.phase_changed.is_connected(_relay_phase_changed):
		_bound_clock.phase_changed.connect(_relay_phase_changed)
	# Re-seed _last_is_day from the new clock's current phase so any stale
	# transition state from when the clock was constructed doesn't spuriously
	# fire on the next tick. Phase 0d heads-up: when MergeCoordinator switches
	# active island during a merge, the joining session's clock may have a
	# very different _last_is_day than the destination island's; the resync
	# here ensures the *next* tick reflects the destination's reality, not a
	# spurious cross-island transition.
	_bound_clock.resync_phase()

func _on_active_island_changed(_island: RefCounted) -> void:
	_bind_to_active_clock()

func _relay_phase_changed(is_day: bool) -> void:
	phase_changed.emit(is_day)

## Called each frame by the engine when this autoload is in the scene tree.
## When constructed via `.new()` (tests), call tick() manually instead.
func _process(delta: float) -> void:
	tick(delta)

# --- Forwarded API ---
#
# Each method resolves the active clock at call time so that switching the
# active island via IslandRegistry.set_active_island() takes effect
# immediately for every caller.

func tick(delta: float) -> void:
	IslandRegistry.active_island().clock.tick(delta)

func set_start_phase(phase: float) -> void:
	IslandRegistry.active_island().clock.set_start_phase(phase)

func advance_to_phase(phase: float) -> void:
	IslandRegistry.active_island().clock.advance_to_phase(phase)

## Phase 0d-i: forward to the active island's clock. Phase 0d-ii will wire
## MergeCoordinator merge events to call this on the lagging clock with a
## ~10s transition. Forwarding through the shim means callers don't need
## to know which DayClockInstance is currently active.
func accelerate_to(target_total_phase: float, duration_seconds: float) -> void:
	IslandRegistry.active_island().clock.accelerate_to(target_total_phase, duration_seconds)

## Phase 0d-i: poll-style "is the active clock currently in a transition?"
## Phase 0d-ii's MergeCoordinator will check this each frame to know when
## the merge transition is complete and the active island can be swapped.
func is_accelerating() -> bool:
	return IslandRegistry.active_island().clock.is_accelerating()

func phase_fraction() -> float:
	return IslandRegistry.active_island().clock.phase_fraction()

func is_daytime() -> bool:
	return IslandRegistry.active_island().clock.is_daytime()

func sky_alpha() -> float:
	return IslandRegistry.active_island().clock.sky_alpha()

func day_count() -> int:
	return IslandRegistry.active_island().clock.day_count()

func moon_phase() -> int:
	return IslandRegistry.active_island().clock.moon_phase()

func moon_fullness() -> float:
	return IslandRegistry.active_island().clock.moon_fullness()

func _get_unix_time() -> float:
	return IslandRegistry.active_island().clock._get_unix_time()
