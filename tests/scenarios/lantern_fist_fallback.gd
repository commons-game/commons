## Scenario: left-clicking with the lantern active harvests like a bare fist.
##
## Trees have HP 3 and fist damage is 1, so 3 clicks must break a tree and
## emit exactly one tile_remove event. No more, no less.
##
## Run:
##   godot4 --path . -- --puppet-scenario=res://tests/scenarios/lantern_fist_fallback.gd
##
## Puppet quits 0 on pass, 1 on fail.
extends Node

const TREE_ATLAS := Vector2i(0, 1)
const TREE_HP    := 3   # must match HARVESTABLE_TILES[TREE_ATLAS].max_hp

func _run(p: Node) -> void:
	await p.wait_ready()
	await p.wait_frames(10)  # give chunk loader time to populate tiles

	p.select_tool(0)
	p.check(p.active_tool_id() == "lantern",
		"expected active tool to be lantern after select_tool(0), got: " + p.active_tool_id())

	var player_pos: Vector2 = p.player().position
	var origin := Vector2i(
		int(floor(player_pos.x / Constants.TILE_SIZE)),
		int(floor(player_pos.y / Constants.TILE_SIZE)),
	)
	var tree_tile := _find_tree_near(p, origin, 8)
	if tree_tile == Vector2i(-9999, -9999):
		p.fail("no tree within 8 tiles of spawn — can't test the harvest path")
		return

	# Teleport adjacent so the tree is always within DIG_RANGE_TILES.
	p.teleport(tree_tile + Vector2i(1, 0))
	await p.wait_frames(2)

	var removes_before: int = EventLog.events_of("tile_remove").size()

	# Player.start_swing() has a 0.5s cooldown, and _tile_damage entries reset
	# after 2s of inactivity. Use wall-clock waits (not frames) so headless
	# perf spikes don't push us past the reset window.
	for i in range(TREE_HP):
		p.click_tile(tree_tile, MOUSE_BUTTON_LEFT)
		await p.wait_seconds(0.55)

	p.check(p.object_atlas_at(tree_tile) == Vector2i(-1, -1),
		"expected tree tile to be removed after %d fist hits, atlas still %s" % [
			TREE_HP, p.object_atlas_at(tree_tile)])

	var removes_after: int = EventLog.events_of("tile_remove").size()
	p.check(removes_after - removes_before == 1,
		"expected exactly 1 tile_remove event, got " + str(removes_after - removes_before))

	# One more click on empty space should be a no-op — no extra removes.
	p.click_tile(tree_tile, MOUSE_BUTTON_LEFT)
	await p.wait_seconds(0.55)
	var removes_final: int = EventLog.events_of("tile_remove").size()
	p.check(removes_final - removes_before == 1,
		"extra click on empty tile triggered another remove: " + str(removes_final - removes_before))

	p.pass_scenario("lantern left-click broke tree in %d hits (fist fallback)" % TREE_HP)

## Scan a box around `origin` for the first tree tile. Returns sentinel if none.
func _find_tree_near(p: Node, origin: Vector2i, radius: int) -> Vector2i:
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r: continue
				var tp := origin + Vector2i(dx, dy)
				if p.object_atlas_at(tp) == TREE_ATLAS:
					return tp
	return Vector2i(-9999, -9999)
