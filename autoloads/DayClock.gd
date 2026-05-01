## DayClock — autoload. Thin wrapper around a single DayClockInstance.
##
## Phase 0a of the per-island clock refactor: the actual time-of-day logic
## now lives in res://world/DayClockInstance.gd (a RefCounted value object).
## This autoload owns one instance and delegates every public call to it.
## External behaviour is unchanged — every call site can keep using
## `DayClock.is_daytime()`, `DayClock.phase_changed`, `DayClock._time_override`,
## etc., exactly as before.
##
## Phase 0b will introduce Island, which owns its own DayClockInstance.
## Phase 0c turns this autoload into a shim that resolves the active island's
## clock instead of holding the instance directly.
##
## All clients still share the same phase automatically because the underlying
## instance derives time from the wall clock (no network sync needed).
##
## Cycle: Constants.DAY_CYCLE_SECONDS (default 7200 = 60 min day + 60 min night)
##   Phase 0.00–0.50 = daytime  (phase_fraction 0 = dawn, 0.25 = midday)
##   Phase 0.50–1.00 = nighttime (0.50 = dusk, 0.75 = midnight)
##
## Testability: set _time_override >= 0 to pin the clock to a fixed unix time.
## (Forwards to the wrapped instance.)
extends Node

const DayClockInstanceScript := preload("res://world/DayClockInstance.gd")

## Re-exported so existing callers reading `DayClock.MOON_PHASE_COUNT` keep working.
const MOON_PHASE_COUNT := DayClockInstanceScript.MOON_PHASE_COUNT

## Emitted when the phase crosses the day/night boundary.
## Re-emitted from the wrapped instance — connections established before
## _ready() ran on this autoload still work because we only forward.
signal phase_changed(is_day: bool)

## The wrapped instance. Held as Object so callers that import
## DayClockInstanceScript don't have to (the class is intentionally not
## globally registered — preload it where needed).
var _instance: Object = null

# --- Forwarded mutable state ---
#
# Some call sites (e.g. World.gd dev hooks, tests) write _time_override
# directly. Expose a property that round-trips to the instance so the
# attribute name stays identical post-extraction.

var _time_override: float:
	get:
		return _instance._time_override
	set(value):
		_instance._time_override = value

var _time_offset: float:
	get:
		return _instance._time_offset
	set(value):
		_instance._time_offset = value

func _init() -> void:
	# Create the instance in _init() (not _ready()) so the wrapper is fully
	# usable as soon as `DayClockScript.new()` returns. The 29 existing
	# autoload tests construct a wrapper, set _time_override on it, and call
	# methods *without* ever adding it to the scene tree — _ready() never
	# fires for them, so the instance must already exist by the time _init()
	# completes.
	_instance = DayClockInstanceScript.new()
	# Re-emit the instance signal so DayClock.phase_changed.connect(...) callers
	# (NightSpawner, DayNightSystem, NightDarkness, Pale, etc.) keep working
	# without any code change.
	_instance.phase_changed.connect(_on_instance_phase_changed)

func _on_instance_phase_changed(is_day: bool) -> void:
	phase_changed.emit(is_day)

func _ready() -> void:
	# Preserve the legacy autoload semantics: the original DayClock seeded
	# _last_is_day in _ready(), i.e. the first time the node entered the
	# scene tree. Tests construct via `.new()`, then set _time_override on the
	# wrapper, *then* add_child() — at which point _ready() fires and the
	# original code re-read is_daytime() from the now-pinned time. We mimic
	# that here so test_day_clock.gd's signal-transition cases keep working
	# without modification.
	_instance.resync_phase()

## Called each frame by the engine when this autoload is in the scene tree.
## When constructed via `.new()` (tests), call tick() manually instead.
func _process(delta: float) -> void:
	tick(delta)

# --- Forwarded API ---

func tick(delta: float) -> void:
	_instance.tick(delta)

func set_start_phase(phase: float) -> void:
	_instance.set_start_phase(phase)

func advance_to_phase(phase: float) -> void:
	_instance.advance_to_phase(phase)

func phase_fraction() -> float:
	return _instance.phase_fraction()

func is_daytime() -> bool:
	return _instance.is_daytime()

func sky_alpha() -> float:
	return _instance.sky_alpha()

func day_count() -> int:
	return _instance.day_count()

func moon_phase() -> int:
	return _instance.moon_phase()

func moon_fullness() -> float:
	return _instance.moon_fullness()

func _get_unix_time() -> float:
	return _instance._get_unix_time()
