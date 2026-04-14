## ChunkData — one 16x16 tile chunk in the world.
## Positioned at pixel offset chunk_coords * CHUNK_SIZE * TILE_SIZE.
## Has two TileMapLayer children: GroundLayer (layer 0) and ObjectLayer (layer 1).
## Collision disabled during bulk _render_all() to avoid per-cell physics rebuilds.
class_name ChunkData
extends Node2D

var chunk_coords: Vector2i
var crdt: CRDTTileStore
var ground_layer: TileMapLayer
var object_layer: TileMapLayer

# Phase 1 fields — declared now, used in Phase 1
var modification_count: int = 0
var last_visited: float = 0.0
var weight: float = 0.0
var is_fading: bool = false

func _ready() -> void:
	ground_layer = $GroundLayer
	object_layer = $ObjectLayer
	crdt = CRDTTileStore.new()

func initialize(coords: Vector2i, entries: Dictionary) -> void:
	chunk_coords = coords
	position = Vector2(coords.x * Constants.CHUNK_SIZE * Constants.TILE_SIZE,
	                   coords.y * Constants.CHUNK_SIZE * Constants.TILE_SIZE)
	crdt.load_from_entries(entries)
	_render_all()

func _render_all() -> void:
	## Disable collision during bulk set to avoid per-cell physics rebuild.
	ground_layer.collision_enabled = false
	object_layer.collision_enabled = false
	ground_layer.clear()
	object_layer.clear()
	for key in crdt.get_all_entries():
		var entry: Dictionary = crdt.get_all_entries()[key]
		if entry["tile_id"] == -1:
			continue  # tombstone — leave cell empty
		var layer_idx: int = (key >> 16) & 0xFF
		var lx: int = (key >> 8) & 0xFF
		var ly: int = key & 0xFF
		var tl := ground_layer if layer_idx == 0 else object_layer
		tl.set_cell(Vector2i(lx, ly), entry["tile_id"],
		            Vector2i(entry["atlas_x"], entry["atlas_y"]), entry["alt_tile"])
	ground_layer.collision_enabled = true
	object_layer.collision_enabled = true

func apply_mutation(layer: int, local: Vector2i, entry: Dictionary) -> void:
	## Apply a single tile mutation without full re-render.
	var tl := ground_layer if layer == 0 else object_layer
	if entry.get("tile_id", -1) == -1:
		tl.erase_cell(local)
	else:
		tl.set_cell(local, entry["tile_id"],
		            Vector2i(entry["atlas_x"], entry["atlas_y"]), entry["alt_tile"])
