## StructureRegistry — maps object-layer atlas coords to structure scene scripts.
##
## Structure scenes (Campfire, Bedroll, Tether, Shrine) are backed by normal
## CRDT object-layer tiles. When ChunkManager loads a chunk it scans the
## entries and, for any atlas coord listed here, instantiates the matching
## script and adds it under the chunk so the visible scene lifecycle follows
## the chunk lifecycle.
##
## This is the ONE place where a new structure type needs to be registered —
## plus the tile atlas itself in TileRegistry and ChunkManager._ensure_tileset_atlas_registered.
##
## Persistence: automatic. Structures live in the chunk's CRDT, so chunk
## save/load already covers them. No owner field is stored — Tether home
## anchors are tracked locally by the player who placed them.
extends Node

var _scripts: Dictionary = {}  # Vector2i atlas → GDScript

func _ready() -> void:
	register(Vector2i(0, 3), preload("res://world/structures/Campfire.gd"))
	register(Vector2i(1, 2), preload("res://world/structures/Workbench.gd"))
	register(Vector2i(1, 3), preload("res://world/structures/Bedroll.gd"))
	register(Vector2i(2, 3), preload("res://world/structures/Tether.gd"))
	register(Vector2i(3, 3), preload("res://world/structures/Shrine.gd"))

func register(atlas: Vector2i, script: GDScript) -> void:
	_scripts[atlas] = script

func script_for(atlas: Vector2i) -> GDScript:
	return _scripts.get(atlas, null)

func is_structure(atlas: Vector2i) -> bool:
	return _scripts.has(atlas)

## Enumerate every registered atlas. Used by ChunkManager when priming its
## TileSet to make sure set_cell() calls don't silently fail.
func all_atlases() -> Array:
	return _scripts.keys()
