## ChunkData — one 16x16 tile chunk in the world.
## Positioned at pixel offset chunk_coords * CHUNK_SIZE * TILE_SIZE.
## Has two TileMapLayer children: GroundLayer (layer 0) and ObjectLayer (layer 1).
##
## Physics batching: ChunkManager calls initialize() BEFORE add_child() so all
## set_cell() calls happen while the node is detached from the scene tree.
## Godot then creates all physics bodies in one pass during _enter_tree() rather
## than one per set_cell() call. This eliminates per-cell physics overhead during
## chunk load. See docs/known_issues.md: "TileMapLayer collision_enabled toggle".
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

var _layers_ready: bool = false

## Atlas positions used by ProceduralGenerator — must be registered before set_cell().
const ATLAS_TILES := [
	Vector2i(0, 0),  # grass
	Vector2i(1, 0),  # dirt
	Vector2i(2, 0),  # stone
	Vector2i(3, 0),  # water
	Vector2i(0, 1),  # tree
	Vector2i(1, 1),  # rock
	Vector2i(2, 1),  # gravestone
	Vector2i(3, 1),  # loot_pickup
	Vector2i(4, 1),  # reeds     (ObjectLayer, no collision, harvestable)
	Vector2i(0, 2),  # campfire  (ObjectLayer, no collision)
	Vector2i(1, 2),  # workbench (ObjectLayer, has collision)
	Vector2i(2, 2),  # plant     (ObjectLayer, no collision, harvestable)
]

func _ready() -> void:
	# _ready() fires when the node enters the scene tree (via add_child).
	# ChunkManager calls initialize() BEFORE add_child(), so layers are already
	# set up by the time _ready() runs. This guard prevents double-init.
	_setup_layers()

## Call once before add_child() to populate tile data while detached from the
## scene tree. Physics bodies are then created in one batch by _enter_tree().
func initialize(coords: Vector2i, entries: Dictionary) -> void:
	_setup_layers()
	chunk_coords = coords
	position = Vector2(coords.x * Constants.CHUNK_SIZE * Constants.TILE_SIZE,
	                   coords.y * Constants.CHUNK_SIZE * Constants.TILE_SIZE)
	crdt.load_from_entries(entries)
	_render_all()

## Set up layer refs and TileSet. Safe to call before add_child() — get_node()
## works on detached trees. Idempotent via _layers_ready guard.
func _setup_layers() -> void:
	if _layers_ready:
		return
	_layers_ready = true

	ground_layer = get_node("GroundLayer") as TileMapLayer
	object_layer = get_node("ObjectLayer") as TileMapLayer
	crdt = CRDTTileStore.new()

	# GroundLayer is never collidable — player always walks on it freely.
	ground_layer.collision_enabled = false

	# Explicit z_index so Player (z=2) always renders above tiles regardless of
	# when chunks are dynamically added to the tree.
	ground_layer.z_index = 0
	object_layer.z_index = 1

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

func _render_all() -> void:
	## When called from initialize() (before add_child), set_cell() calls are free —
	## no physics bodies are created until _enter_tree() batches them all at once.
	## When called later (e.g. apply_crdt_snapshot), the chunk is in the tree and
	## each set_cell() creates a physics body immediately — acceptable since snapshots
	## are rare. GroundLayer collision is permanently disabled.
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

	# TileData uses a centred coordinate system: (0,0) is the tile centre.
	var h := float(Constants.TILE_SIZE) * 0.5

	# Ground tiles (grass/dirt/stone) get full-tile shapes but GroundLayer has
	# collision_enabled=false so they never generate physics bodies. The shapes
	# are defined anyway so the same TileSet can be reused if collision is ever
	# toggled on programmatically (e.g. in tests or future mechanics).
	var full_poly := PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h),
		Vector2(h,  h),  Vector2(-h,  h),
	])

	# Object tiles (tree/rock) use a bottom-half shape. The visual footprint of a
	# tree fills the whole tile, but only blocking the lower portion lets the player
	# walk near the crown without getting stuck in dense forest. Keeping it 70% wide
	# avoids hair-thin gaps between adjacent trees.
	var bottom_poly := PackedVector2Array([
		Vector2(-h * 0.7, 0.0), Vector2(h * 0.7, 0.0),
		Vector2(h * 0.7,  h),   Vector2(-h * 0.7,  h),
	])

	var tile_polys := {
		Vector2i(0, 0): full_poly,   # grass  (GroundLayer only → no bodies)
		Vector2i(1, 0): full_poly,   # dirt   (GroundLayer only → no bodies)
		Vector2i(2, 0): full_poly,   # stone  (GroundLayer only → no bodies)
		# water (3,0) intentionally omitted — no collision
		Vector2i(0, 1): bottom_poly, # tree      (ObjectLayer → blocks at trunk)
		Vector2i(1, 1): bottom_poly, # rock      (ObjectLayer → blocks at base)
		Vector2i(2, 1): bottom_poly, # gravestone (ObjectLayer → blocks at base)
		# loot_pickup (3,1) intentionally omitted — no collision, player walks over it
		# campfire (0,2) intentionally omitted — no collision, player walks over it
		Vector2i(1, 2): bottom_poly, # workbench (ObjectLayer → blocks at base)
	}
	for coords in tile_polys:
		if not source.has_tile(coords):
			continue
		var td := source.get_tile_data(coords, 0)
		if td == null:
			continue
		if td.get_collision_polygons_count(0) == 0:
			td.set_collision_polygons_count(0, 1)
		td.set_collision_polygon_points(0, 0, tile_polys[coords])

func apply_mutation(layer: int, local: Vector2i, entry: Dictionary) -> void:
	## Apply a single tile mutation without full re-render.
	var tl := ground_layer if layer == 0 else object_layer
	if entry.get("tile_id", -1) == -1:
		tl.erase_cell(local)
	else:
		tl.set_cell(local, entry["tile_id"],
		            Vector2i(entry["atlas_x"], entry["atlas_y"]), entry["alt_tile"])
