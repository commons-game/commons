## Scenario: left-clicking with the lantern active must never mutate tiles.
##
## Regression target: bug where TileInteraction fell through to melee for the
## lantern tool and harvested trees one click at a time. See commit history.
##
## Run:
##   godot4 --path . -- --puppet-scenario=res://tests/scenarios/lantern_no_delete.gd
##
## Puppet quits 0 on pass, 1 on fail.
extends Node

const TREE_ATLAS := Vector2i(0, 1)

func _run(p: Node) -> void:
	await p.wait_ready()
	await p.wait_frames(10)  # give chunk loader time to populate tiles

	# Select tool slot 0 (lantern by default) and confirm.
	p.select_tool(0)
	p.check(p.active_tool_id() == "lantern",
		"expected active tool to be lantern after select_tool(0), got: " + p.active_tool_id())

	# Find a tree near the player. If there's no tree in the viewport, fail loudly
	# so the scenario author knows to pick a seeded area.
	var player_pos: Vector2 = p.player().position
	var origin := Vector2i(
		int(floor(player_pos.x / Constants.TILE_SIZE)),
		int(floor(player_pos.y / Constants.TILE_SIZE)),
	)
	var tree_tile := _find_tree_near(p, origin, 8)
	if tree_tile == Vector2i(-9999, -9999):
		p.fail("no tree within 8 tiles of spawn — can't test the harvest regression")
		return

	# Snapshot all object tiles in a 17x17 box around spawn, click the tree
	# several times, then confirm nothing moved.
	var tl := origin - Vector2i(8, 8)
	var br := origin + Vector2i(8, 8)
	var before: Dictionary = p.snapshot_objects(tl, br)

	for i in range(5):
		p.click_tile(tree_tile, MOUSE_BUTTON_LEFT)
		await p.wait_frames(2)

	var after: Dictionary = p.snapshot_objects(tl, br)

	# Compare every key.
	var changed_keys: Array = []
	for k in before.keys():
		if before[k] != after[k]:
			changed_keys.append(k)

	if changed_keys.size() > 0:
		p.fail("lantern click mutated tile(s): " + str(changed_keys))
		return

	# Also verify the EventLog: click events logged, zero tile_remove events.
	var clicks: Array = EventLog.events_of("click")
	p.check(clicks.size() >= 5,
		"expected ≥5 click events in EventLog, got " + str(clicks.size()))

	var removes: Array = EventLog.events_of("tile_remove")
	p.check(removes.size() == 0,
		"expected 0 tile_remove events, got " + str(removes.size()))

	p.pass_scenario("5 lantern clicks on a tree, 0 tile mutations")

## Scan a box around `origin` for the first tree tile. Returns sentinel if none.
func _find_tree_near(p: Node, origin: Vector2i, radius: int) -> Vector2i:
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r: continue  # ring of radius r
				var tp := origin + Vector2i(dx, dy)
				if p.object_atlas_at(tp) == TREE_ATLAS:
					return tp
	return Vector2i(-9999, -9999)
