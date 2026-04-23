## Cross-peer scenario: peer A places a Tether (their home anchor); peer B
## breaks it. Peer A's home state must clear via the tile_removed signal that
## the mirror fires on A's bus, even though B originated the remove.
##
## Locks the wiring I introduced in the Tether migration: home-anchor lives
## on the Player, listens to TileMutationBus.tile_removed, doesn't depend on
## who ran the request. A regression here = "you can break an enemy's Tether
## but they keep respawning at home."
extends Node

const TETHER_ATLAS := Vector2i(2, 3)

func _run(ps: Array) -> void:
	var a: Node = ps[0]
	var b: Node = ps[1]

	await a.wait_seconds(0.3)

	var tile := Vector2i(4, 1)
	if a.has_object_at(tile):
		a.world().get_node("TileMutationBus").request_remove_tile(tile, 1)
		await a.wait_seconds(0.05)

	# Peer A places their Tether; a's Player tracks this tile as home.
	a.world().get_node("TileMutationBus").request_place_tile(tile, 1, "tether")
	a.player().home_pos = Vector2(tile.x * Constants.TILE_SIZE + 8, tile.y * Constants.TILE_SIZE + 8)
	a.player()._has_home = true
	a.player()._home_tile_pos = tile
	await a.wait_seconds(0.1)

	a.check(a.object_atlas_at(tile) == TETHER_ATLAS, "peer A missing tether atlas")
	a.check(b.object_atlas_at(tile) == TETHER_ATLAS, "peer B didn't see tether mirror")
	a.check(bool(a.player()._has_home), "peer A's _has_home should be true after placement")

	# Peer B breaks the Tether. A's Player should react via tile_removed signal.
	b.world().get_node("TileMutationBus").request_remove_tile(tile, 1)
	await a.wait_seconds(0.1)

	a.check(a.object_atlas_at(tile) != TETHER_ATLAS,
		"peer A still sees tether atlas after peer B removed")
	a.check(not bool(a.player()._has_home),
		"peer A's home should clear when an enemy breaks their Tether, still _has_home=true")

	a.pass_scenario("cross-peer tether break clears the owner's home anchor")
