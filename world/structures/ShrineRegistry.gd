## ShrineRegistry — autoload singleton tracking one active Shrine per player.
##
## Each player can have at most one Shrine in the world at a time.
## When a second Shrine is placed by the same player, the first is removed.
##
## Pattern mirrors TetherRegistry.
extends Node

## Maps player_id (String) → Shrine Node2D reference.
var _shrines: Dictionary = {}  # String -> Node2D (Shrine)

## Register a Shrine for a player. If one already exists it is removed first.
func register_shrine(player_id: String, shrine_node: Node2D) -> void:
	if _shrines.has(player_id):
		var old: Node2D = _shrines[player_id] as Node2D
		if is_instance_valid(old):
			old.queue_free()
	_shrines[player_id] = shrine_node

## Unregister a Shrine. Called when the Shrine node is freed.
func unregister_shrine(player_id: String) -> void:
	_shrines.erase(player_id)

## Return the active Shrine node for player_id, or null if none.
func get_shrine(player_id: String) -> Node2D:
	if not _shrines.has(player_id):
		return null
	var node: Node2D = _shrines[player_id] as Node2D
	if not is_instance_valid(node):
		_shrines.erase(player_id)
		return null
	return node

## Return true if player_id currently has a live Shrine in the world.
func has_shrine(player_id: String) -> bool:
	return get_shrine(player_id) != null

## Return all live Shrine nodes (stale entries are pruned).
func get_all() -> Array:
	var result: Array = []
	var stale: Array = []
	for pid in _shrines:
		var node: Node2D = _shrines[pid] as Node2D
		if is_instance_valid(node):
			result.append(node)
		else:
			stale.append(pid)
	for pid in stale:
		_shrines.erase(pid)
	return result
