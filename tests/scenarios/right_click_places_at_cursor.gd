## Scenario: right-click while wielding a placeable structure places at the
## *cursor tile* (not the player-facing tile), within a 4-tile Chebyshev range,
## and snaps player facing toward the target.
##
## Regression target: pre-fix, _place_structure ignored the mouse and always
## placed one tile in the direction of _facing. Right-click felt detached from
## where the cursor was — players would aim at a spot 3 tiles east and the
## structure would appear directly above them because _facing happened to be UP.
## The same handler is used by all 5 placeables (campfire, bedroll, tether,
## shrine, workbench) so the fix uniformly affects all of them.
##
## Run:
##   godot4 --headless --path . -- --puppet-scenario=res://tests/scenarios/right_click_places_at_cursor.gd
extends Node

const WORKBENCH_ATLAS := Vector2i(1, 2)

func _run(p: Node) -> void:
	await p.wait_ready()
	await p.wait_frames(5)

	var world: Node = p.world()
	var bus: Node = world.get_node_or_null("TileMutationBus")
	p.check(bus != null, "World has no TileMutationBus")

	var inv: Object = p.player().inventory

	# -----------------------------------------------------------------------
	# (i) Place a workbench 2 tiles east of the player (player facing UP, so
	# pre-fix this would have placed at player + (0,-1) instead of the target).
	# -----------------------------------------------------------------------
	var player_tile := _player_tile(p)
	var target_i := player_tile + Vector2i(2, 0)
	if p.has_object_at(target_i):
		bus.request_remove_tile(target_i, 1)
		await p.wait_frames(2)

	inv.add_to_bag({"id": "workbench", "category": "structure", "count": 1}, 1)
	# Force facing UP so a "facing-derived" placement would land at (0,-1).
	p.player()._facing = Vector2(0, -1)
	await p.wait_frames(1)

	# Drive the new entry point: right-click at a target tile (not just the id).
	# The handler should be: _place_structure(item_id, target_tile).
	p.player().call("_place_structure", "workbench", target_i)
	await p.wait_frames(3)

	p.check(p.object_atlas_at(target_i) == WORKBENCH_ATLAS,
		"workbench should land at clicked tile %s — got atlas %s. " % [target_i, p.object_atlas_at(target_i)]
		+ "Pre-fix it would have placed at facing-derived %s." % [player_tile + Vector2i(0, -1)])
	# Sanity: the facing-derived tile must be empty (proves it didn't place there).
	var facing_derived := player_tile + Vector2i(0, -1)
	if facing_derived != target_i:
		p.check(p.object_atlas_at(facing_derived) != WORKBENCH_ATLAS,
			"workbench accidentally also placed at facing-derived tile %s — handler is firing both paths" % facing_derived)

	# -----------------------------------------------------------------------
	# (ii) Out-of-range placement (6 tiles east) should be a silent no-op:
	# nothing placed, item still in inventory.
	# -----------------------------------------------------------------------
	inv.add_to_bag({"id": "workbench", "category": "structure", "count": 1}, 1)
	var before_count: int = inv.bag_stack_total("workbench")
	var far_tile := player_tile + Vector2i(6, 0)
	if p.has_object_at(far_tile):
		bus.request_remove_tile(far_tile, 1)
		await p.wait_frames(2)
	p.player().call("_place_structure", "workbench", far_tile)
	await p.wait_frames(3)
	p.check(p.object_atlas_at(far_tile) != WORKBENCH_ATLAS,
		"out-of-range placement at %s should have been a no-op, but a workbench appeared" % far_tile)
	var after_count: int = inv.bag_stack_total("workbench")
	p.check(after_count == before_count,
		"out-of-range placement consumed inventory (had %d, now %d) — silent no-op should leave bag untouched" % [before_count, after_count])

	# -----------------------------------------------------------------------
	# (iii) Diagonal NE placement updates _facing toward (1, -1) normalized.
	# -----------------------------------------------------------------------
	inv.add_to_bag({"id": "workbench", "category": "structure", "count": 1}, 1)
	var ne_tile := player_tile + Vector2i(2, -2)
	if p.has_object_at(ne_tile):
		bus.request_remove_tile(ne_tile, 1)
		await p.wait_frames(2)
	# Reset facing to something orthogonal so the diagonal change is visible.
	p.player()._facing = Vector2(-1, 0)
	await p.wait_frames(1)
	p.player().call("_place_structure", "workbench", ne_tile)
	await p.wait_frames(3)

	var expected_facing := Vector2(1, -1).normalized()
	var actual_facing: Vector2 = p.player()._facing
	var facing_delta: float = (actual_facing - expected_facing).length()
	p.check(facing_delta < 0.01,
		"facing should snap to (1,-1) normalized (~%s) after placing at NE tile, got %s (delta %f)" \
			% [expected_facing, actual_facing, facing_delta])
	p.check(p.object_atlas_at(ne_tile) == WORKBENCH_ATLAS,
		"diagonal placement at %s failed — atlas %s" % [ne_tile, p.object_atlas_at(ne_tile)])

	p.pass_scenario("right-click places at cursor tile within 4-tile range and snaps facing toward target")

func _player_tile(p: Node) -> Vector2i:
	return Vector2i(
		int(floor(p.player().position.x / Constants.TILE_SIZE)),
		int(floor(p.player().position.y / Constants.TILE_SIZE)))
