## Scenario: Shrine tile persists across chunk unload/reload; ShrineRegistry
## tracks it by tile position and World's proximity iteration sees it.
##
## Run:
##   godot4 --headless --path . -- --puppet-scenario=res://tests/scenarios/shrine_persists.gd
extends Node

const SHRINE_ATLAS := Vector2i(3, 3)

func _run(p: Node) -> void:
	await p.wait_ready()
	await p.wait_frames(5)

	var world: Node = p.world()
	var bus: Node = world.get_node_or_null("TileMutationBus")
	var cm: Node = world.get_node_or_null("ChunkManager")
	p.check(bus != null and cm != null, "World missing bus or ChunkManager")

	var tile := Vector2i(
		int(floor(p.player().position.x / Constants.TILE_SIZE)),
		int(floor(p.player().position.y / Constants.TILE_SIZE))) + Vector2i(3, 0)
	if p.has_object_at(tile):
		bus.request_remove_tile(tile, 1)
		await p.wait_frames(2)

	bus.request_place_tile(tile, 1, "shrine")
	await p.wait_frames(3)

	p.check(p.object_atlas_at(tile) == SHRINE_ATLAS, "shrine atlas missing")
	p.check(ShrineRegistry.has_shrine_at(tile),
		"ShrineRegistry doesn't know about the placed Shrine")

	var shrines_before: Array = ShrineRegistry.get_all()
	p.check(shrines_before.size() >= 1, "get_all() returned empty after place")

	# Chunk round-trip.
	var chunk_coords: Vector2i = CoordUtils.world_to_chunk(tile)
	cm.call("_unload_chunk", chunk_coords)
	await p.wait_frames(2)
	cm.call("_load_chunk", chunk_coords)
	await p.wait_frames(5)

	p.check(p.object_atlas_at(tile) == SHRINE_ATLAS, "shrine atlas lost after reload")
	p.check(ShrineRegistry.has_shrine_at(tile),
		"ShrineRegistry missing Shrine after chunk reload")

	# Remove → registry should forget.
	bus.request_remove_tile(tile, 1)
	await p.wait_frames(3)
	p.check(not ShrineRegistry.has_shrine_at(tile),
		"ShrineRegistry still has an entry after remove")

	p.pass_scenario("shrine persists and registry tracks it by tile pos")
