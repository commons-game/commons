## ShiftingLandsSystem — tracks whether the world is "shifted" (players split)
## and decides which chunks drift to alien biomes.
##
## Wiring (in World._setup_merge_system):
##   _coordinator.split_occurred.connect(_shifting_lands._on_split_occurred)
##   _coordinator.merge_ready.connect(_shifting_lands._on_merge_ready)
##   chunk_manager.shifting_lands = _shifting_lands
##
## Quantum observer rule: only chunks NOT currently loaded can drift.
## ChunkManager passes the current loaded set via is_chunk_shifted(coords).
extends Node

const DRIFT_START_DELAY := 5.0   ## seconds after split before any drift begins
const DRIFT_RATE := 0.12         ## probability per second of drifting (once delay passes)

var _split: bool = false
var _split_time: float = 0.0
var _shift_seed: int = 0
var _drifted: Dictionary = {}    ## Vector2i -> bool

## True while split (players have diverged).
func is_split() -> bool:
	return _split

## The alternate seed used to generate shifted chunks.
func get_shift_seed() -> int:
	return _shift_seed

## Returns true if this chunk coord should use shifted generation.
## Called by ChunkManager._load_chunk() for fresh (not on-disk) chunks only.
## Uses stochastic, time-gated drift decision cached per coord.
func is_chunk_shifted(coords: Vector2i) -> bool:
	if not _split:
		return false
	if _drifted.has(coords):
		return _drifted[coords]
	var elapsed := Time.get_unix_time_from_system() - _split_time
	if elapsed < DRIFT_START_DELAY:
		_drifted[coords] = false
		return false
	var probability := minf(0.95, (elapsed - DRIFT_START_DELAY) * DRIFT_RATE)
	var drifted := randf() < probability
	_drifted[coords] = drifted
	return drifted

## Called when players diverge. Partner seed must be set separately.
func _on_split_occurred() -> void:
	_split = true
	_split_time = Time.get_unix_time_from_system()
	_drifted.clear()
	print("ShiftingLands: split — drift begins in %.1fs" % DRIFT_START_DELAY)

## Called when players merge (CRDT exchange begins).
## Drifted chunks will reload fresh from the merged CRDT state.
func _on_merge_ready(_remote_session_id: String) -> void:
	if not _split:
		return
	_split = false
	_drifted.clear()
	print("ShiftingLands: merge — drift cleared, CRDT reconciliation in progress")

## Set the seed to derive shifted terrain from.
## World calls this when it knows the remote session ID.
func set_partner_seed(remote_session_id: String) -> void:
	_shift_seed = remote_session_id.hash()

## Returns a list of drifted chunk coords (for debug/HUD use).
func get_drifted_coords() -> Array:
	var result: Array = []
	for k in _drifted:
		if _drifted[k]:
			result.append(k)
	return result
