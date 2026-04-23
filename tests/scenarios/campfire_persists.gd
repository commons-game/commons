## Scenario: placing a campfire stores it as a CRDT object-layer tile, and
## unloading + reloading the chunk respawns the scene node from persistence.
##
## Regression target: structures used to live only as World-level Node2Ds.
## On game quit they vanished. This scenario asserts the first step of
## structure persistence — chunk unload + reload preserves the campfire.
##
## Run:
##   godot4 --headless --path . -- --puppet-scenario=res://tests/scenarios/campfire_persists.gd
extends Node

const CAMPFIRE_ATLAS := Vector2i(0, 3)

func _run(p: Node) -> void:
	await p.wait_ready()
	await p.wait_frames(5)

	# Place a campfire tile directly via the bus — same path Player uses after
	# the migration. We skip the Player UI flow so the scenario isolates the
	# persistence plumbing from inventory/tool semantics.
	var world: Node = p.world()
	var bus: Node = world.get_node_or_null("TileMutationBus")
	p.check(bus != null, "World has no TileMutationBus")

	# Tile near the player so its chunk is definitely loaded.
	var tile := Vector2i(
		int(floor(p.player().position.x / Constants.TILE_SIZE)),
		int(floor(p.player().position.y / Constants.TILE_SIZE))) + Vector2i(1, 0)

	# Clear anything already on layer 1 at that tile (tests may hit trees).
	if p.has_object_at(tile):
		bus.request_remove_tile(tile, 1)
		await p.wait_frames(2)

	bus.request_place_tile(tile, 1, "campfire")
	await p.wait_frames(3)

	# Step 1: the CRDT has the tile.
	p.check(p.object_atlas_at(tile) == CAMPFIRE_ATLAS,
		"campfire atlas missing at %s after place (got %s)" % [tile, p.object_atlas_at(tile)])

	# Step 2: a Campfire scene exists on the chunk.
	var campfire_before: Node = _find_campfire_at(world, tile)
	p.check(campfire_before != null,
		"no Campfire scene spawned at %s after place" % tile)

	# Step 3: force the chunk to unload (persists to disk) then reload
	# without restarting the scene.
	var cm: Node = world.get_node_or_null("ChunkManager")
	p.check(cm != null, "World has no ChunkManager")
	var chunk_coords: Vector2i = CoordUtils.world_to_chunk(tile)

	# Bump modification_count so the unload actually persists (the manager
	# skips serialisation for unchanged chunks).
	var chunk_before: Node = cm.call("get_chunk", chunk_coords)
	p.check(chunk_before != null, "chunk %s not loaded" % chunk_coords)

	# Internal API: _unload_chunk → _load_chunk round-trip through Backend.
	cm.call("_unload_chunk", chunk_coords)
	await p.wait_frames(2)
	cm.call("_load_chunk", chunk_coords)
	await p.wait_frames(5)

	# Step 4: atlas survived.
	p.check(p.object_atlas_at(tile) == CAMPFIRE_ATLAS,
		"campfire atlas lost after chunk reload (got %s)" % p.object_atlas_at(tile))

	# Step 5: a Campfire scene node was re-spawned by _load_chunk.
	var campfire_after: Node = _find_campfire_at(world, tile)
	p.check(campfire_after != null,
		"Campfire scene not re-spawned after chunk reload")
	p.check(campfire_after != campfire_before,
		"Expected a fresh Campfire instance after reload (same instance would mean unload didn't fire)")

	p.pass_scenario("campfire tile persists and scene re-spawns across chunk unload/reload")

## Walk the Chunk children looking for a Campfire with the given world_tile_pos.
## The scene is spawned under its owning chunk, not directly under World.
func _find_campfire_at(world: Node, world_tile: Vector2i) -> Node:
	var cm: Node = world.get_node_or_null("ChunkManager")
	if cm == null:
		return null
	for chunk in cm.get_children():
		if not (chunk is Node2D):
			continue
		for child in chunk.get_children():
			if child.get_class() != "Node2D":
				# Script classes identify via their script path rather than
				# get_class, so check the script resource.
				var s := child.get_script() as Resource
				if s == null:
					continue
				if not str(s.resource_path).ends_with("/Campfire.gd"):
					continue
			if "world_tile_pos" in child and child.world_tile_pos == world_tile:
				return child
	return null
