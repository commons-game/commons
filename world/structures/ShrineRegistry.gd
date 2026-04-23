## ShrineRegistry — autoload view over placed Shrine scenes, keyed by world
## tile position.
##
## Shrines are ownerless — every Shrine is an independent world entity. The
## registry provides a cheap "get all Shrines" lookup for systems like
## proximity checks and territory calculations.
##
## Pattern mirrors TetherRegistry / CampfireRegistry.
extends Node

var _shrines: Dictionary = {}  # Vector2i tile_pos → Node2D (Shrine)

func register_shrine(tile_pos: Vector2i, shrine_node: Node2D) -> void:
	_shrines[tile_pos] = shrine_node

func unregister_shrine(tile_pos: Vector2i) -> void:
	_shrines.erase(tile_pos)

func shrine_at(tile_pos: Vector2i) -> Node2D:
	var node: Node2D = _shrines.get(tile_pos, null) as Node2D
	if node != null and not is_instance_valid(node):
		_shrines.erase(tile_pos)
		return null
	return node

func has_shrine_at(tile_pos: Vector2i) -> bool:
	return shrine_at(tile_pos) != null

## Return all live Shrine nodes (stale entries are pruned on read).
func get_all() -> Array:
	var result: Array = []
	var stale: Array = []
	for k in _shrines:
		var node: Node2D = _shrines[k] as Node2D
		if is_instance_valid(node):
			result.append(node)
		else:
			stale.append(k)
	for k in stale:
		_shrines.erase(k)
	return result
