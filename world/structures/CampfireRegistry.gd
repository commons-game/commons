## CampfireRegistry — autoload singleton tracking all active placed campfires.
##
## NightSpawner queries get_campfire_positions() to avoid spawning near campfires.
## Sprout steering queries nearest_campfire_world_pos() to steer around them.
extends Node

## List of world-tile Vector2i positions for every active campfire node.
var _campfire_positions: Array = []  # Array[Vector2i]

## Register a campfire at a world-tile position. Called by placed Campfire nodes.
func register_campfire(world_tile_pos: Vector2i) -> void:
	if not _campfire_positions.has(world_tile_pos):
		_campfire_positions.append(world_tile_pos)

## Unregister a campfire. Called when a Campfire node is removed.
func unregister_campfire(world_tile_pos: Vector2i) -> void:
	_campfire_positions.erase(world_tile_pos)

## Return a copy of the current campfire positions array.
func get_campfire_positions() -> Array:
	return _campfire_positions.duplicate()

## Return the nearest campfire tile position to a given world-tile position,
## or Vector2i(-9999, -9999) if no campfires exist.
func nearest_campfire_tile(query: Vector2i) -> Vector2i:
	if _campfire_positions.is_empty():
		return Vector2i(-9999, -9999)
	var best: Vector2i = _campfire_positions[0]
	var best_dist: float = (best - query).length()
	for pos in _campfire_positions:
		var d: float = (pos - query).length()
		if d < best_dist:
			best_dist = d
			best = pos
	return best
