## DayClock — autoload. Derives day/night phase from real unix time.
##
## All clients share the same phase automatically because they all derive it
## from the same wall clock with no network sync needed.
##
## Cycle: DAY_CYCLE_SECONDS = 7200 (60 min day + 60 min night)
##   Phase 0.00–0.50 = daytime  (phase_fraction 0 = dawn, 0.25 = midday)
##   Phase 0.50–1.00 = nighttime (0.50 = dusk, 0.75 = midnight)
##
## sky_alpha(): darkness overlay opacity — 0.0 at midday, 1.0 at midnight.
##
## Testability: set _time_override >= 0 to pin the clock to a fixed unix time.
extends Node

## Emitted when the phase crosses the day/night boundary.
signal phase_changed(is_day: bool)

## Set to a non-negative value to pin the clock to a fixed unix time (tests only).
var _time_override: float = -1.0

## Added to real unix time so the cycle starts at a desired phase.
## Set via set_start_phase() — does not stop the clock ticking.
var _time_offset: float = 0.0

## Shift the clock so the cycle phase is `phase` right now, then let it run.
func set_start_phase(phase: float) -> void:
	var real_now := Time.get_unix_time_from_system()
	var current_phase := fmod(real_now, Constants.DAY_CYCLE_SECONDS) / Constants.DAY_CYCLE_SECONDS
	var delta_phase := phase - current_phase
	_time_offset = delta_phase * Constants.DAY_CYCLE_SECONDS

var _last_is_day: bool = true

func _ready() -> void:
	_last_is_day = is_daytime()

## Called each frame (or manually via tick() in tests).
func _process(delta: float) -> void:
	tick(delta)

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

# --- Internal ---

func _get_unix_time() -> float:
	if _time_override >= 0.0:
		return _time_override
	return Time.get_unix_time_from_system() + _time_offset
