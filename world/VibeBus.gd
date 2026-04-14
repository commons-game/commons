## VibeBus — two-axis ambient state machine for the world's emotional layer.
##
## Axes:
##   tension  [0, 1] — danger / conflict energy (0 = calm, 1 = combat)
##   tone     [0, 1] — environmental warmth   (0 = cold/hostile, 1 = welcoming)
##
## API:
##   push(source_id, tension_delta, tone_delta, decay_seconds)
##     Register or replace a named contribution. Decays linearly to zero over
##     decay_seconds. Pushing the same source_id replaces the previous entry.
##
##   get_tension() / get_tone()
##     Return the sum of all living contributions, clamped to [0, 1].
##
## Signal:
##   vibe_shifted(tension: float, tone: float)
##     Emitted when the combined state changes. Fired during tick() whenever
##     any contribution was just added or is actively decaying.
##
## Usage: add as a child of World. Call push() from any system that wants to
## influence the ambient vibe (merge pressure, combat, weather, shrines, etc.).
extends Node

signal vibe_shifted(tension: float, tone: float)

## Internal contribution record.
## { tension: float, tone: float, decay_seconds: float, elapsed: float }
var _contributions: Dictionary = {}  # source_id (String) -> Dictionary
var _dirty: bool = false

## Add or replace a named contribution.
func push(source_id: String, tension_delta: float, tone_delta: float,
		decay_seconds: float) -> void:
	_contributions[source_id] = {
		"tension": clampf(tension_delta, 0.0, 1.0),
		"tone":    clampf(tone_delta,    0.0, 1.0),
		"decay":   maxf(decay_seconds, 0.001),
		"elapsed": 0.0,
	}
	_dirty = true

## Return summed tension across all living contributions, clamped [0, 1].
func get_tension() -> float:
	return clampf(_sum_axis("tension"), 0.0, 1.0)

## Return summed tone across all living contributions, clamped [0, 1].
func get_tone() -> float:
	return clampf(_sum_axis("tone"), 0.0, 1.0)

## Advance time. Called by _process or directly in tests via tick().
func tick(delta: float) -> void:
	var has_active := false
	var to_remove: Array = []
	for sid in _contributions:
		var c: Dictionary = _contributions[sid]
		c["elapsed"] += delta
		if c["elapsed"] >= c["decay"]:
			to_remove.append(sid)
		else:
			has_active = true
	for sid in to_remove:
		_contributions.erase(sid)
		_dirty = true
	if _dirty or has_active:
		vibe_shifted.emit(get_tension(), get_tone())
		_dirty = false

func _process(delta: float) -> void:
	tick(delta)

# --- Internal ---

func _sum_axis(axis: String) -> float:
	var total := 0.0
	for sid in _contributions:
		var c: Dictionary = _contributions[sid]
		var remaining: float = 1.0 - (float(c["elapsed"]) / float(c["decay"]))
		total += float(c[axis]) * remaining
	return total
