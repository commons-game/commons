## TetherRegistry — autoload singleton tracking one active Tether per player.
##
## Each player can have at most one Tether in the world at a time.
## When a second Tether is placed by the same player, the first is removed.
##
## Pattern mirrors CampfireRegistry.
extends Node

## Maps player_id (String) → Tether Node2D reference.
var _tethers: Dictionary = {}  # String -> Node2D (Tether)

## Register a Tether for a player. If one already exists it is removed first.
func register_tether(player_id: String, tether_node: Node2D) -> void:
	if _tethers.has(player_id):
		var old: Node2D = _tethers[player_id] as Node2D
		if is_instance_valid(old):
			old.queue_free()
	_tethers[player_id] = tether_node

## Unregister a Tether. Called when the Tether node is freed.
func unregister_tether(player_id: String) -> void:
	_tethers.erase(player_id)

## Return the active Tether node for player_id, or null if none.
func get_tether(player_id: String) -> Node2D:
	if not _tethers.has(player_id):
		return null
	var node: Node2D = _tethers[player_id] as Node2D
	if not is_instance_valid(node):
		_tethers.erase(player_id)
		return null
	return node

## Return true if player_id currently has a live Tether in the world.
func has_tether(player_id: String) -> bool:
	return get_tether(player_id) != null
