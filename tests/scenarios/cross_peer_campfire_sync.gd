## Cross-peer scenario: placement and removal mirror between two Worlds via
## the TileMutationBus test-peer bridge. Exercises RPC-equivalent code paths
## (apply_remote_mutation) plus structure spawn/despawn on both sides.
##
## Invariants asserted:
##   1. Peer A places a campfire → its tile is visible on peer B's ChunkManager
##   2. Peer B spawns a Campfire scene at the same world_tile_pos as peer A's
##   3. Peer B removes the tile → peer A's scene despawns
##
## Run:
##   godot4 --headless --path . -- --puppet-cluster-scenario=res://tests/scenarios/cross_peer_campfire_sync.gd
extends Node

const CAMPFIRE_ATLAS := Vector2i(0, 3)

func _run(ps: Array) -> void:
	var a: Node = ps[0]
	var b: Node = ps[1]

	await a.wait_seconds(0.3)  # let both chunk loaders catch up

	# Pick a tile near peer A's player that's also in range of peer B's loaded
	# chunks. Peer B's player spawns at (0,0) just like A (single-process,
	# identical spawn), so the same world tile works for both.
	var tile := Vector2i(3, 0)
	if a.has_object_at(tile):
		var bus_a_pre: Node = a.world().get_node("TileMutationBus")
		bus_a_pre.request_remove_tile(tile, 1)
		await a.wait_seconds(0.05)

	# Peer A places the campfire.
	var bus_a: Node = a.world().get_node("TileMutationBus")
	bus_a.request_place_tile(tile, 1, "campfire")
	await a.wait_seconds(0.1)

	# Invariant 1: peer B's tile_store sees the tile.
	a.check(b.object_atlas_at(tile) == CAMPFIRE_ATLAS,
		"expected peer B to see campfire atlas at %s, got %s" % [tile, b.object_atlas_at(tile)])

	# Invariant 2: peer B has a Campfire scene under its chunk at world_tile_pos.
	var b_scene: Node = _find_structure_at(b.world(), tile, "Campfire.gd")
	a.check(b_scene != null, "peer B has no Campfire scene at %s after peer A placed" % tile)

	# Peer A also has its own Campfire (the request was local to A).
	var a_scene: Node = _find_structure_at(a.world(), tile, "Campfire.gd")
	a.check(a_scene != null, "peer A has no Campfire scene at %s" % tile)

	# Peer B removes the tile.
	var bus_b: Node = b.world().get_node("TileMutationBus")
	bus_b.request_remove_tile(tile, 1)
	await a.wait_seconds(0.1)

	# Invariant 3: peer A's tile and scene are gone.
	a.check(a.object_atlas_at(tile) != CAMPFIRE_ATLAS,
		"peer A still shows campfire atlas after peer B removed (got %s)" % a.object_atlas_at(tile))
	var a_scene_after: Node = _find_structure_at(a.world(), tile, "Campfire.gd")
	a.check(a_scene_after == null, "peer A's Campfire scene survived peer B's remove")

	# And peer B also despawned its own local scene.
	var b_scene_after: Node = _find_structure_at(b.world(), tile, "Campfire.gd")
	a.check(b_scene_after == null, "peer B's own Campfire scene not despawned on remove")

	a.pass_scenario("campfire place and remove synced between 2 peers")

## Walk a World's chunks for a scripted child at the given world_tile_pos.
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
