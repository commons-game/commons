## StatusEffectSystem — base-game duration/magnitude effect tracker.
##
## Distinct from BuffManager, which handles shrine-scoped mod buffs.
## Effects here are base-game mechanics: status conditions (poison, slow, haste),
## environmental effects, item effects. They have duration and magnitude but no
## shrine affiliation — their lifecycle is purely time-based.
##
## Duration <= 0 means permanent: the effect never expires on its own.
##
## Usage:
##   sys.add_effect("poison", 5.0, 1.0)   # 5s duration, magnitude 1.0
##   sys.add_effect("aura",   0.0, 2.0)   # permanent
##   sys.tick(delta)                       # call each frame (or use _process)
##   sys.has_effect("poison")              # → bool
##   sys.get_effect_magnitude("poison")    # → float
##   sys.remove_effect("poison")           # explicit removal
extends Node

## Emitted when a duration-based effect expires naturally.
signal effect_expired(effect_id: String)
## Emitted whenever the active effect list changes (add, remove, or expiry).
signal effects_changed(effects: Array)

# effect_id -> { id, duration, magnitude, remaining }
var _effects: Dictionary = {}

## Add (or replace) an effect. duration <= 0 means permanent.
func add_effect(effect_id: String, duration: float, magnitude: float) -> void:
	_effects[effect_id] = {
		"id":        effect_id,
		"duration":  duration,
		"magnitude": magnitude,
		"remaining": duration,
	}
	effects_changed.emit(get_active_effects())

## Explicitly remove an effect. No-op if not present.
func remove_effect(effect_id: String) -> void:
	if not _effects.has(effect_id):
		return
	_effects.erase(effect_id)
	effects_changed.emit(get_active_effects())

## Returns true if the effect is currently active.
func has_effect(effect_id: String) -> bool:
	return _effects.has(effect_id)

## Returns the magnitude of an active effect, or 0.0 if absent.
func get_effect_magnitude(effect_id: String) -> float:
	if not _effects.has(effect_id):
		return 0.0
	return _effects[effect_id]["magnitude"]

## Returns a snapshot of all active effects as an Array of Dictionaries.
func get_active_effects() -> Array:
	return _effects.values().duplicate()

## Advance time by delta seconds, expiring any elapsed duration-based effects.
## Called automatically by _process; may also be called manually in tests.
func tick(delta: float) -> void:
	var expired: Array = []
	for id in _effects:
		var e: Dictionary = _effects[id]
		if e["duration"] <= 0.0:
			continue  # permanent — never expires
		e["remaining"] -= delta
		if e["remaining"] <= 0.0:
			expired.append(id)
	if expired.is_empty():
		return
	for id in expired:
		_effects.erase(id)
		effect_expired.emit(id)
	effects_changed.emit(get_active_effects())

func _process(delta: float) -> void:
	tick(delta)
