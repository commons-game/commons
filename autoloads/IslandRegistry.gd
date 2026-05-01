## IslandRegistry — singleton tracking all islands in the current session.
##
## Phase 0b of the per-island clock refactor: the registry creates one default
## implicit island at startup, used by solo / pre-merge state. island_for()
## currently ignores its argument and always returns the default island.
##
## Phase 0c will wire DayClock to resolve through this registry (autoload
## becomes a thin shim: DayClock.is_daytime() -> IslandRegistry.island_for(
## local_player).clock.is_daytime()).
##
## Phase 0d will create / merge / destroy non-default islands in response to
## MergeCoordinator events. For now the registry is single-island and static,
## but register_island() / unregister_island() are exposed so 0d only has to
## wire callers, not extend the API.
extends Node

const IslandScript := preload("res://world/Island.gd")
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
