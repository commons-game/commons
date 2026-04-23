## Scenario: bedroll tile placement persists across chunk unload/reload, and
## the Bedroll scene re-spawns on reload. Same pattern as campfire_persists.gd.
##
## Run:
##   godot4 --headless --path . -- --puppet-scenario=res://tests/scenarios/bedroll_persists.gd
extends Node

const BEDROLL_ATLAS := Vector2i(1, 3)

func _run(p: Node) -> void:
	await p.wait_ready()
	await p.wait_frames(5)

	var world: Node = p.world()
	var bus: Node = world.get_node_or_null("TileMutationBus")
	p.check(bus != null, "World has no TileMutationBus")

	var tile := Vector2i(
		int(floor(p.player().position.x / Constants.TILE_SIZE)),
		int(floor(p.player().position.y / Constants.TILE_SIZE))) + Vector2i(0, 1)
	if p.has_object_at(tile):
		bus.request_remove_tile(tile, 1)
		await p.wait_frames(2)

	bus.request_place_tile(tile, 1, "bedroll")
	await p.wait_frames(3)

	p.check(p.object_atlas_at(tile) == BEDROLL_ATLAS,
		"bedroll atlas missing at %s (got %s)" % [tile, p.object_atlas_at(tile)])

	var before: Node = _find_structure_at(world, tile, "Bedroll.gd")
	p.check(before != null, "no Bedroll scene spawned at %s" % tile)

	var cm: Node = world.get_node_or_null("ChunkManager")
	var chunk_coords: Vector2i = CoordUtils.world_to_chunk(tile)
	cm.call("_unload_chunk", chunk_coords)
	await p.wait_frames(2)
	cm.call("_load_chunk", chunk_coords)
	await p.wait_frames(5)

	p.check(p.object_atlas_at(tile) == BEDROLL_ATLAS,
		"bedroll atlas lost after chunk reload")

	var after: Node = _find_structure_at(world, tile, "Bedroll.gd")
	p.check(after != null, "Bedroll scene not re-spawned after chunk reload")
	p.check(after != before, "expected a fresh Bedroll instance after reload")

	p.pass_scenario("bedroll tile persists and scene re-spawns across chunk reload")

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
