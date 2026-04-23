## Cross-peer scenario: peer B's chunk isn't loaded when peer A places a
## structure in it. When peer B later loads that chunk (walks into it, or
## explicitly via _load_chunk), the structure must materialise from the
## shared storage / CRDT state rather than being lost.
##
## Models a late-joiner or a player visiting territory someone else built —
## the most common cross-peer scenario that ISN'T covered by live RPC.
extends Node

const CAMPFIRE_ATLAS := Vector2i(0, 3)

func _run(ps: Array) -> void:
	var a: Node = ps[0]
	var b: Node = ps[1]

	await a.wait_seconds(0.3)

	# Pick a tile in a chunk near spawn that's loaded on A, then force-unload
	# the same chunk on B so B is the "late joiner" for that area.
	var tile := Vector2i(5, 5)
	if a.has_object_at(tile):
		a.world().get_node("TileMutationBus").request_remove_tile(tile, 1)
		await a.wait_seconds(0.05)

	var chunk_coords: Vector2i = CoordUtils.world_to_chunk(tile)
	var cm_b: Node = b.world().get_node("ChunkManager")
	# Force B's chunk unload BEFORE A places — simulates B never having loaded it.
	cm_b.call("_unload_chunk", chunk_coords)
	await a.wait_seconds(0.05)

	# Peer A places. B's apply_remote_mutation will warn ("place_tile on
	# unloaded chunk") and bail — but A's store_chunk writes to the shared
	# InMemoryBackend, so the structure exists in persistent state.
	a.world().get_node("TileMutationBus").request_place_tile(tile, 1, "campfire")
	# Give A's chunk a chance to flush to the shared backend by explicitly
	# unloading it (ChunkManager persists on unload when modification_count > 0).
	var cm_a: Node = a.world().get_node("ChunkManager")
	cm_a.call("_unload_chunk", chunk_coords)
	cm_a.call("_load_chunk", chunk_coords)
	await a.wait_seconds(0.1)

	# Now B loads the chunk. Its _spawn_structures_for_chunk should pick up
	# the campfire from the CRDT entries retrieved from shared storage.
	cm_b.call("_load_chunk", chunk_coords)
	await a.wait_seconds(0.2)

	a.check(b.object_atlas_at(tile) == CAMPFIRE_ATLAS,
		"peer B didn't see campfire atlas after joining chunk (got %s)" % b.object_atlas_at(tile))
	var b_scene: Node = _find_structure_at(b.world(), tile, "Campfire.gd")
	a.check(b_scene != null,
		"peer B's Campfire scene not spawned on chunk load (expected from CRDT entries)")

	a.pass_scenario("late joiner sees existing structure via shared storage on chunk load")

func _find_structure_at(world: Node, world_tile: Vector2i, script_suffix: String) -> Node:
	var cm: Node = world.get_node_or_null("ChunkManager")
	if cm == null:
		return null
	for chunk in cm.get_children():
		for child in chunk.get_children():
			var s := child.get_script() as Resource
			if s == null:
				continue
			if not str(s.resource_path).ends_with(script_suffix):
				continue
			if "world_tile_pos" in child and child.world_tile_pos == world_tile:
				return child
	return null
