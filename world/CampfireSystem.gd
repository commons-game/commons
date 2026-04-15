## CampfireSystem — maintains PointLight2D nodes at campfire tile positions.
##
## Polls loaded chunks every POLL_INTERVAL_S and adds/removes PointLight2D
## nodes to match the positions of campfire tiles (atlas 0,2) on layer 1.
##
## Lights are parented to the World node (set via the parent) so they persist
## across chunk reloads. Positions are cleaned up when a campfire tile is
## removed or a chunk is unloaded.
##
## Usage (in World.gd):
##   var _campfire_system := CampfireSystemScript.new()
##   _campfire_system._chunk_mgr = $ChunkManager
##   add_child(_campfire_system)
extends Node

## How often (seconds) to scan loaded chunks for campfire tiles.
const POLL_INTERVAL_S := 2.0

## PointLight2D properties for campfires.
const LIGHT_COLOR  := Color(1.0, 0.6, 0.1)
const LIGHT_ENERGY := 1.5
const LIGHT_RANGE  := 96.0   # pixels (6 tiles at 16px)

## world_pos (Vector2i) → PointLight2D
var _lights: Dictionary = {}

## Set by World after construction.
var _chunk_mgr: Node = null

var _poll_timer: float = 0.0

func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL_S:
		_poll_timer = 0.0
		_sync_lights()

func _sync_lights() -> void:
	if _chunk_mgr == null:
		return

	# Collect all campfire world positions from loaded chunks.
	var campfire_positions: Dictionary = {}  # Vector2i → true

	var chunk_coords_list: Array = _chunk_mgr.get_loaded_chunk_coords()
	for cc in chunk_coords_list:
		var chunk = _chunk_mgr.get_chunk(cc as Vector2i)
		if chunk == null or not is_instance_valid(chunk):
			continue
		var chunk_origin := Vector2i(
			int(chunk.chunk_coords.x) * Constants.CHUNK_SIZE,
			int(chunk.chunk_coords.y) * Constants.CHUNK_SIZE)
		var used: Array = chunk.object_layer.get_used_cells()
		for local_cell in used:
			var lc: Vector2i = local_cell as Vector2i
			var source_id: int = chunk.object_layer.get_cell_source_id(lc)
			if source_id < 0:
				continue
			var atlas: Vector2i = chunk.object_layer.get_cell_atlas_coords(lc)
			if atlas == Vector2i(0, 2):  # campfire
				var world_pos := chunk_origin + lc
				campfire_positions[world_pos] = true

	# Remove lights for positions that no longer have a campfire.
	var stale: Array = []
	for pos in _lights:
		if not campfire_positions.has(pos):
			stale.append(pos)
	for pos in stale:
		var light = _lights[pos]
		if is_instance_valid(light):
			light.queue_free()
		_lights.erase(pos)

	# Add lights for new campfire positions.
	for pos in campfire_positions:
		if _lights.has(pos):
			continue
		var light := PointLight2D.new()
		# Center light on the tile.
		light.position = Vector2(
			int(pos.x) * Constants.TILE_SIZE + Constants.TILE_SIZE * 0.5,
			int(pos.y) * Constants.TILE_SIZE + Constants.TILE_SIZE * 0.5 - 4.0)
		light.color  = LIGHT_COLOR
		light.energy = LIGHT_ENERGY
		light.texture_scale = LIGHT_RANGE / 32.0  # default Godot light texture is 64px radius
		light.z_index = 3
		get_parent().add_child(light)
		_lights[pos] = light
