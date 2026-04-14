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

## Atlas positions used by ProceduralGenerator — must be registered before set_cell().
const ATLAS_TILES := [
	Vector2i(0, 0),  # grass
	Vector2i(1, 0),  # dirt
	Vector2i(2, 0),  # stone
	Vector2i(3, 0),  # water
	Vector2i(0, 1),  # tree
	Vector2i(1, 1),  # rock
]

func _ready() -> void:
	ground_layer = $GroundLayer
	object_layer = $ObjectLayer
	crdt = CRDTTileStore.new()

	# GroundLayer is never collidable — player always walks on it freely.
	ground_layer.collision_enabled = false

	# Register atlas positions on the actual TileSet instance used by this chunk.
	# Doing it here (not in ChunkManager) handles the case where PackedScene
	# instantiation deep-copies the TileSet resource rather than sharing it.
	# Explicitly set TileSet tile_size — omitting this in the .tres leaves it at (0,0)
	# which silently prevents TileMapLayer from rendering any tiles.
	ground_layer.tile_set.tile_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
	var source := ground_layer.tile_set.get_source(0) as TileSetAtlasSource
	assert(source != null, "Chunk GroundLayer TileSet has no source — this chunk will render blank")
	if source:
		# Explicitly set region size to match our 16x16 tile PNG layout.
		source.texture_region_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
		for coords in ATLAS_TILES:
			if not source.has_tile(coords):
				source.create_tile(coords)
		_ensure_tileset_collision(ground_layer.tile_set, source)

func initialize(coords: Vector2i, entries: Dictionary) -> void:
	chunk_coords = coords
	position = Vector2(coords.x * Constants.CHUNK_SIZE * Constants.TILE_SIZE,
	                   coords.y * Constants.CHUNK_SIZE * Constants.TILE_SIZE)
	crdt.load_from_entries(entries)
	_render_all()

func _render_all() -> void:
	## Temporarily disable ObjectLayer collision during bulk set to avoid
	## per-cell physics rebuilds. GroundLayer stays disabled permanently.
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
	object_layer.collision_enabled = true

## Set up a single TileSet physics layer and add full-tile collision polygons to
## all non-water tiles. Called once per shared TileSet instance (guarded by
## get_physics_layers_count() == 0). GroundLayer has collision_enabled = false
## so ground tiles never block movement regardless of their collision shape.
func _ensure_tileset_collision(tileset: TileSet, source: TileSetAtlasSource) -> void:
	if tileset.get_physics_layers_count() > 0:
		return  # already set up by a previous Chunk instance
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)
	tileset.set_physics_layer_collision_mask(0, 1)

	# Full-tile collision quad in TileData local space.
	# TileData uses a centred coordinate system: (0,0) is the tile centre.
	var h := float(Constants.TILE_SIZE) * 0.5
	var poly := PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h),
		Vector2(h, h),  Vector2(-h, h),
	])

	# Add collision to all collidable tiles (everything except water).
	var collidable := [
		Vector2i(0, 0),  # grass
		Vector2i(1, 0),  # dirt
		Vector2i(2, 0),  # stone
		Vector2i(0, 1),  # tree
		Vector2i(1, 1),  # rock
		# water (3,0) intentionally omitted — no collision
	]
	for coords in collidable:
		if not source.has_tile(coords):
			continue
		var td := source.get_tile_data(coords, 0)
		if td == null:
			continue
		if td.get_collision_polygons_count(0) == 0:
			td.set_collision_polygons_count(0, 1)
		td.set_collision_polygon_points(0, 0, poly)

func apply_mutation(layer: int, local: Vector2i, entry: Dictionary) -> void:
	## Apply a single tile mutation without full re-render.
	var tl := ground_layer if layer == 0 else object_layer
	if entry.get("tile_id", -1) == -1:
		tl.erase_cell(local)
	else:
		tl.set_cell(local, entry["tile_id"],
		            Vector2i(entry["atlas_x"], entry["atlas_y"]), entry["alt_tile"])
