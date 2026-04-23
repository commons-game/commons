## TetherRegistry — autoload view over placed Tether scenes, keyed by world
## tile position.
##
## Indexed by tile coord rather than owner id because Tether tiles are
## ownerless — each Player tracks which tile is their home anchor locally
## (see Player._home_tile_pos). The registry exists so callers can answer
## "is there a Tether at this tile?" without scanning the chunk tree.
##
## Pattern mirrors CampfireRegistry.
extends Node

var _tethers: Dictionary = {}  # Vector2i tile_pos → Node2D (Tether)

func register_tether(tile_pos: Vector2i, tether_node: Node2D) -> void:
	_tethers[tile_pos] = tether_node

func unregister_tether(tile_pos: Vector2i) -> void:
	_tethers.erase(tile_pos)

func tether_at(tile_pos: Vector2i) -> Node2D:
	var node: Node2D = _tethers.get(tile_pos, null) as Node2D
	if node != null and not is_instance_valid(node):
		_tethers.erase(tile_pos)
		return null
	return node

func has_tether_at(tile_pos: Vector2i) -> bool:
	return tether_at(tile_pos) != null

func get_all() -> Array:
	# Prune stale entries on read.
	for k in _tethers.keys():
		if not is_instance_valid(_tethers[k]):
			_tethers.erase(k)
	return _tethers.values()
