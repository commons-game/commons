## Scenario: left-clicking a tile orients the player toward that tile.
##
## Regression target: TileInteraction routed left-clicks to the tile under the
## cursor (correct), but Player._facing kept whatever value the last WASD
## input had set. So the character visibly faced UP while harvesting a tree
## to their EAST. Visual feedback (the direction triangle) was decoupled from
## what the player was actually attacking.
##
## The fix: TileInteraction notifies the player which tile it's about to swing
## at, and Player snaps _facing to point from its tile toward the click.
## We re-use the existing DIG_RANGE_TILES (5) range check for the harvest
## itself — this commit doesn't change the range, just the facing.
##
## Run:
##   godot4 --headless --path . -- --puppet-scenario=res://tests/scenarios/left_click_faces_target.gd
extends Node

const ATLAS_TREE := Vector2i(0, 1)

func _run(p: Node) -> void:
	await p.wait_ready()
	await p.wait_frames(5)

	var world: Node = p.world()
	var bus: Node = world.get_node_or_null("TileMutationBus")
	p.check(bus != null, "World has no TileMutationBus")

	# -----------------------------------------------------------------------
	# (i) Tree at (player + (3, 0)). Player facing UP. Left-click should snap
	# facing to (1, 0) regardless of the prior facing value.
	# -----------------------------------------------------------------------
	var player_tile := _player_tile(p)
	var east_tree := player_tile + Vector2i(3, 0)
	if p.has_object_at(east_tree):
		bus.request_remove_tile(east_tree, 1)
		await p.wait_frames(2)
	bus.request_place_tile(east_tree, 1, "tree")
	await p.wait_frames(3)
	p.check(p.object_atlas_at(east_tree) == ATLAS_TREE,
		"setup: tree didn't get placed at %s (got %s)" % [east_tree, p.object_atlas_at(east_tree)])

	p.player()._facing = Vector2(0, -1)
	await p.wait_frames(1)
	p.click_tile(east_tree, MOUSE_BUTTON_LEFT)
	await p.wait_frames(3)

	var expected_east := Vector2(1, 0)
	var actual_east: Vector2 = p.player()._facing
	var d_east: float = (actual_east - expected_east).length()
	p.check(d_east < 0.01,
		"left-click on tile %s (player at %s) should snap facing to (1,0), got %s (delta %f)" \
			% [east_tree, player_tile, actual_east, d_east])

	# -----------------------------------------------------------------------
	# (ii) Tree at (player + (0, -3)). Left-click should snap facing to (0, -1).
	# Player is currently facing east (from step (i)), so this proves the snap
	# overrides the stale facing.
	# -----------------------------------------------------------------------
	var north_tree := player_tile + Vector2i(0, -3)
	if p.has_object_at(north_tree):
		bus.request_remove_tile(north_tree, 1)
		await p.wait_frames(2)
	bus.request_place_tile(north_tree, 1, "tree")
	await p.wait_frames(3)
	p.check(p.object_atlas_at(north_tree) == ATLAS_TREE,
		"setup: tree didn't get placed at %s (got %s)" % [north_tree, p.object_atlas_at(north_tree)])

	p.click_tile(north_tree, MOUSE_BUTTON_LEFT)
	await p.wait_frames(3)

	var expected_north := Vector2(0, -1)
	var actual_north: Vector2 = p.player()._facing
	var d_north: float = (actual_north - expected_north).length()
	p.check(d_north < 0.01,
		"left-click on tile %s (player at %s) should snap facing to (0,-1), got %s (delta %f)" \
			% [north_tree, player_tile, actual_north, d_north])

	p.pass_scenario("left-click snaps player facing toward the clicked tile")

func _player_tile(p: Node) -> Vector2i:
	return Vector2i(
		int(floor(p.player().position.x / Constants.TILE_SIZE)),
		int(floor(p.player().position.y / Constants.TILE_SIZE)))
