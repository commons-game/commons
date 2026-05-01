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

var _islands: Dictionary = {}  # id (String) -> Island (RefCounted)
var _default_island: RefCounted

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
