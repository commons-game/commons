## TileRegistry — maps string tile IDs to tileset data (tile_id, atlas, alt).
##
## Usage:
##   TileRegistry.register("grass", 0, Vector2i(0, 0))
##   var entry := TileRegistry.resolve("grass")
##   # entry = {tile_id: 0, atlas: Vector2i(0,0), alt: 0}
##
## Mods call register() during their _ready() to add tile types.
## Built-in tiles are registered below.
extends Node

var _entries: Dictionary = {}

func _ready() -> void:
	# Atlas layout: row 0 = ground tiles, row 1 = object tiles
	register("default", 0, Vector2i(0, 0), 0)  # alias for grass
	register("grass",   0, Vector2i(0, 0), 0)
	register("dirt",    0, Vector2i(1, 0), 0)
	register("stone",   0, Vector2i(2, 0), 0)
	register("water",   0, Vector2i(3, 0), 0)
	register("tree",    0, Vector2i(0, 1), 0)
	register("rock",    0, Vector2i(1, 1), 0)

func register(tile_name: String, tile_id: int, atlas: Vector2i, alt: int = 0) -> void:
	_entries[tile_name] = {"tile_id": tile_id, "atlas": atlas, "alt": alt}

func resolve(tile_name: String) -> Dictionary:
	return _entries.get(tile_name, {})

func has_tile(tile_name: String) -> bool:
	return _entries.has(tile_name)
