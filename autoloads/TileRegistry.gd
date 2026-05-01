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
	# Reeds — water-adjacent harvestable spawned by ProceduralGenerator in
	# Verdant + Tangle. Bare-hand-harvested; yields the "reeds" material item
	# (see ItemRegistry). Slot (4,1) is in the row-1 harvestables cluster
	# alongside tree and rock.
	register("reeds",   0, Vector2i(4, 1), 0)
	register("ether_crystal", 0, Vector2i(3, 2), 0)
	# Structure tiles. The visible scene is spawned by ChunkManager via
	# StructureRegistry; the atlas entry exists so set_cell() accepts it,
	# but the tile texture itself is blank — only the scene node renders.
	register("campfire",  0, Vector2i(0, 3), 0)
	register("workbench", 0, Vector2i(1, 2), 0)
	register("bedroll",   0, Vector2i(1, 3), 0)
	register("tether",    0, Vector2i(2, 3), 0)
	register("shrine",    0, Vector2i(3, 3), 0)

func register(tile_name: String, tile_id: int, atlas: Vector2i, alt: int = 0) -> void:
	_entries[tile_name] = {"tile_id": tile_id, "atlas": atlas, "alt": alt}

func resolve(tile_name: String) -> Dictionary:
	return _entries.get(tile_name, {})

func has_tile(tile_name: String) -> bool:
	return _entries.has(tile_name)
