## DayClockInstance — a standalone day/night clock.
##
## Phase 0a of the per-island clock refactor: the time-of-day logic that
## used to live in the DayClock autoload now lives here, on a RefCounted
## value object. Multiple instances can coexist (Phase 0b will give each
## Island its own), and the autoload (Phase 0a) holds exactly one and
## forwards every call to it. External behaviour is unchanged.
##
## Cycle: Constants.DAY_CYCLE_SECONDS (default 7200 = 60 min day + 60 min night)
##   Phase 0.00–0.50 = daytime  (phase_fraction 0 = dawn, 0.25 = midday)
##   Phase 0.50–1.00 = nighttime (0.50 = dusk, 0.75 = midnight)
##
## sky_alpha(): darkness overlay opacity — 0.0 at midday, 1.0 at midnight.
##
## Testability: set _time_override >= 0 to pin the clock to a fixed unix time.
## This is a value object, not a Node — it has no _process(); the autoload
## (or whoever owns it) must call tick(delta) each frame.
extends RefCounted

## Emitted when the phase crosses the day/night boundary.
signal phase_changed(is_day: bool)

## Set to a non-negative value to pin the clock to a fixed unix time (tests only).
var _time_override: float = -1.0

## Added to real unix time so the cycle starts at a desired phase.
## Set via set_start_phase() — does not stop the clock ticking.
var _time_offset: float = 0.0

## Tracks the most recently observed phase so tick() can detect transitions.
var _last_is_day: bool = true

## Phase 0d-i: wall-time mock for testing the accelerate_to() ramp.
## Set >= 0 to pin "now" for both the ramp's elapsed-time calculation AND
## the offset-additive `_get_unix_time()` path. Distinct from `_time_override`
## (which short-circuits the whole clock and is therefore incompatible with
## offset arithmetic — there's no way for a `_time_override`-pinned clock to
## also reflect a moving ramp). Production never sets this; tests use it
## instead of sleeping on the wall clock.
var _wall_time_override: float = -1.0

const MOON_PHASE_COUNT := 8

# --- Phase 0d-i: clock acceleration primitive ---
#
# `accelerate_to(target_total_phase, duration_seconds)` ramps `_time_offset`
# upward over `duration_seconds` of wall time so that the clock's total phase
# (day_count + phase_fraction) lands on `target_total_phase` at the end of
# the ramp. The ramp is resolved on every read via `_effective_offset()` —
# DayClockInstance has no driver (it's RefCounted, no _process), so settling
# the ramp inside the read path is the cleanest way to keep it driverless.
# When wall time crosses the ramp's end, the next read commits the extra
# offset into `_time_offset` permanently and zeros the ramp state, so all
# subsequent reads take the cheap fast path.
#
# The ramp is monotonic forward: a target that's <= the current total phase
# is a no-op (the leading clock in a merge never accelerates backward).

## Wall time when accelerate_to() was called. -1.0 means no active ramp.
var _accel_start_wall_time: float = -1.0
## Duration of the active ramp in seconds. 0.0 means inactive.
var _accel_duration_seconds: float = 0.0
## Total seconds of extra offset to apply by the end of the ramp.
var _accel_extra_offset: float = 0.0
## `_time_offset` at the moment accelerate_to() was called — the ramp adds
## linearly to this base, so reading mid-ramp is `_accel_base_offset +
## _accel_extra_offset * t`.
var _accel_base_offset: float = 0.0

func _init() -> void:
	# Mirror the autoload's _ready() initialisation: seed _last_is_day from
	# the current phase so the first tick() doesn't spuriously emit. Owners
	# that mutate _time_override after construction should call resync_phase()
	# to re-seed from the new pinned time (the autoload wrapper does this in
	# its own _ready() to preserve the legacy "seed at scene-tree-entry"
	# semantics that test_day_clock.gd relies on).
	_last_is_day = is_daytime()

## Re-seed _last_is_day from the current phase. Call after mutating
## _time_override or _time_offset out-of-band so the next tick() doesn't
## spuriously emit a phase_changed for a transition that was actually a
## reseat of the time source.
func resync_phase() -> void:
	_last_is_day = is_daytime()

## Shift the clock so the cycle phase is `phase` right now, then let it run.
func set_start_phase(phase: float) -> void:
	var delta_phase := phase - phase_fraction()
	_apply_time_delta(delta_phase * Constants.DAY_CYCLE_SECONDS)

## Jump the clock *forward* until phase_fraction() == phase. Never rewinds.
## Use for "respawn at dawn" — we want time to move, not unwind.
## phase_changed will emit on the next tick if we crossed the day/night boundary.
func advance_to_phase(phase: float) -> void:
	var delta_phase := phase - phase_fraction()
	if delta_phase < 0.0:
		delta_phase += 1.0  # wrap forward to next cycle
	_apply_time_delta(delta_phase * Constants.DAY_CYCLE_SECONDS)

## Shifts the active time source by delta_sec. Honours _time_override when set
## so tests using pinned clocks also see the clock advance.
func _apply_time_delta(delta_sec: float) -> void:
	if _time_override >= 0.0:
		_time_override += delta_sec
	else:
		_time_offset += delta_sec

## Phase 0d-i: ramp the clock forward so its total phase reaches
## `target_total_phase` after `duration_seconds` of wall-clock time.
##
## "Total phase" is `day_count() + phase_fraction()` — a monotonically
## increasing measure of how far into the cycle history we are. Use this when
## a lagging island merges into a leading one: the lagging clock accelerates
## to catch up with the leader's total phase over the merge transition.
##
## No-op (and logs a push_error) if the target is at or behind the current
## total phase. Phase 0d-ii's MergeCoordinator is responsible for routing
## the call to the *lagging* clock, never the leading one.
func accelerate_to(target_total_phase: float, duration_seconds: float) -> void:
	var current_total_phase := float(day_count()) + phase_fraction()
	if target_total_phase <= current_total_phase:
		# Lagging-only invariant violated. push_error so the bug is loud in
		# debug builds without breaking the caller (Phase 0d-ii merge logic
		# may legitimately race against a clock that's already caught up).
		push_error("DayClockInstance.accelerate_to: target %.4f <= current %.4f (clock cannot rewind)" % [target_total_phase, current_total_phase])
		return
	_accel_extra_offset = (target_total_phase - current_total_phase) * Constants.DAY_CYCLE_SECONDS
	_accel_duration_seconds = duration_seconds
	_accel_start_wall_time = _now_wall()
	_accel_base_offset = _time_offset

## True while a ramp is in progress. Phase 0d-ii will poll this from
## MergeCoordinator to know when convergence is complete and the active
## island can be swapped. Returns false both before any accelerate_to() and
## after the ramp has committed (a subsequent read of any time-derived
## method auto-commits when wall time passes the ramp end).
func is_accelerating() -> bool:
	return _accel_duration_seconds > 0.0

## Returns the current `_time_offset` adjusted for any active acceleration
## ramp. When wall time crosses the ramp end, this method has the side
## effect of committing the ramp into `_time_offset` and zeroing the ramp
## state — that's how the driverless design works (the read settles the
## ramp). The mutation is idempotent: once committed, subsequent calls take
## the cheap fast path that just returns `_time_offset`.
func _effective_offset() -> float:
	if _accel_duration_seconds <= 0.0:
		return _time_offset
	var elapsed := _now_wall() - _accel_start_wall_time
	var t := clampf(elapsed / _accel_duration_seconds, 0.0, 1.0)
	if t >= 1.0:
		# Commit the ramp: bake the extra offset into `_time_offset`
		# permanently and clear the ramp state. From this point on the
		# clock runs at wall-time pace again.
		_time_offset = _accel_base_offset + _accel_extra_offset
		_accel_duration_seconds = 0.0
		_accel_extra_offset = 0.0
		_accel_start_wall_time = -1.0
		return _time_offset
	return _accel_base_offset + _accel_extra_offset * t

## Owner (autoload, World, etc.) calls this each frame so phase_changed can fire
## on day/night boundary crossings. delta is currently unused — kept for API
## symmetry with Node._process(delta).
func tick(_delta: float) -> void:
	var now_day := is_daytime()
	if now_day != _last_is_day:
		_last_is_day = now_day
		phase_changed.emit(now_day)

## Returns position within the full cycle as a value in [0, 1).
func phase_fraction() -> float:
	return fmod(_get_unix_time(), Constants.DAY_CYCLE_SECONDS) / Constants.DAY_CYCLE_SECONDS

## Returns true during the daytime half of the cycle (phase_fraction < 0.5).
func is_daytime() -> bool:
	return phase_fraction() < 0.5

## Returns darkness overlay alpha: 0.0 at midday, 1.0 at midnight.
## Uses a smooth sinusoidal curve so transitions feel gradual.
func sky_alpha() -> float:
	# phase_fraction: 0=dawn, 0.25=midday, 0.5=dusk, 0.75=midnight
	# Shift cosine by -0.25 so the minimum (cos=1→alpha=0) lands at midday,
	# and the maximum (cos=-1→alpha=1) lands at midnight.
	var angle := (phase_fraction() - 0.25) * TAU
	return clampf((1.0 - cos(angle)) * 0.5, 0.0, 1.0)

# --- Moon phases ---
#
# Moon advances one phase per in-game day; 8 phases cycle every ~16 hours real time
# at DAY_CYCLE_SECONDS=7200. Phase index: 0=new, 4=full; moon_fullness() is symmetric
# around phase 4 so you get new → waxing → full → waning → new as a triangle wave.

## Integer day count since unix epoch (offset-aware).
func day_count() -> int:
	return int(floor(_get_unix_time() / Constants.DAY_CYCLE_SECONDS))

## Current moon phase index. 0=new, 4=full. Advances at each dawn.
func moon_phase() -> int:
	var c := day_count() % MOON_PHASE_COUNT
	if c < 0: c += MOON_PHASE_COUNT
	return c

## Moon "fullness" in [0, 1]. 0 = new moon (pitch dark), 1 = full moon (bright).
## Symmetric: phases 0..4 rise linearly to full, phases 4..8 fall back to new.
func moon_fullness() -> float:
	var p := moon_phase()
	return 1.0 - abs(p - 4) / 4.0

# --- Internal ---

func _get_unix_time() -> float:
	if _time_override >= 0.0:
		return _time_override
	return _now_wall() + _effective_offset()

## Phase 0d-i: wall-time accessor. Returns `_wall_time_override` when set
## (>= 0), else `Time.get_unix_time_from_system()`. Used both by `_get_unix_time`
## and by the acceleration ramp's elapsed-time calculation so that a single
## test knob (`_wall_time_override`) drives both the ramp and the clock's
## reading of "now". Production never sets `_wall_time_override`, so the
## branch is always the wall-clock path outside tests.
func _now_wall() -> float:
	if _wall_time_override >= 0.0:
		return _wall_time_override
	return Time.get_unix_time_from_system()
