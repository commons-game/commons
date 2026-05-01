## Scenario: KEY_C is the only crafting key. CraftingUI auto-detects workbench
## proximity at open-time and unlocks workbench recipes accordingly.
##
## Regression target: pre-fix, players had to remember TWO keys — C for hand
## crafting (2×2 grid) and E for workbench mode (3×3 grid). The split was
## arbitrary: standing next to a workbench, "press C" gave you a hand-only
## menu and the workbench was inert; "press E" opened the workbench menu but
## only when next to one. Unified flow: C always opens, the menu adapts.
##
## Run:
##   godot4 --headless --path . -- --puppet-scenario=res://tests/scenarios/crafting_unified_by_proximity.gd
extends Node

const WORKBENCH_ATLAS := Vector2i(1, 2)

func _run(p: Node) -> void:
	await p.wait_ready()
	await p.wait_frames(5)

	var world: Node = p.world()
	var bus: Node = world.get_node_or_null("TileMutationBus")
	p.check(bus != null, "World has no TileMutationBus")
	var cui: Node = world.get_node_or_null("CraftingUI")
	p.check(cui != null, "World has no CraftingUI")

	# -----------------------------------------------------------------------
	# (i) Far from any workbench: KEY_C opens, _workbench_mode == false,
	# grid is 2×2 (4 slots), hand recipes available.
	# -----------------------------------------------------------------------
	var player_tile := _player_tile(p)
	# Make sure there's no workbench within range of the player by clearing
	# any object tiles within WORKBENCH_RANGE+1.
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var t := player_tile + Vector2i(dx, dy)
			if p.object_atlas_at(t) == WORKBENCH_ATLAS:
				bus.request_remove_tile(t, 1)
	await p.wait_frames(3)

	# Sanity: closed at start.
	if bool(cui.visible):
		cui.call("hide_ui")
		await p.wait_frames(1)
	p.check(not bool(cui.visible), "sanity: CraftingUI should be hidden before C-press")

	_press_c(p)
	await p.wait_frames(3)

	p.check(bool(cui.visible), "CraftingUI should open after pressing C")
	p.check(not bool(cui._workbench_mode),
		"far from workbench, _workbench_mode should be false (got true) — proximity check missing")
	p.check(int(cui._grid.size()) == 4,
		"hand-mode grid should be 4 slots (2×2), got %d" % int(cui._grid.size()))

	# Close before next phase.
	cui.call("hide_ui")
	await p.wait_frames(2)

	# -----------------------------------------------------------------------
	# (ii) Place a workbench adjacent to the player, press C → workbench mode.
	# -----------------------------------------------------------------------
	var wb_tile := player_tile + Vector2i(1, 0)
	if p.has_object_at(wb_tile):
		bus.request_remove_tile(wb_tile, 1)
		await p.wait_frames(2)
	bus.request_place_tile(wb_tile, 1, "workbench")
	await p.wait_frames(3)
	p.check(p.object_atlas_at(wb_tile) == WORKBENCH_ATLAS,
		"setup: workbench didn't get placed at %s" % wb_tile)

	_press_c(p)
	await p.wait_frames(3)

	p.check(bool(cui.visible), "CraftingUI should open after pressing C near workbench")
	p.check(bool(cui._workbench_mode),
		"adjacent to workbench, _workbench_mode should be true (got false) — proximity check broken")
	p.check(int(cui._grid.size()) == 9,
		"workbench-mode grid should be 9 slots (3×3), got %d" % int(cui._grid.size()))

	# Confirm workbench-only recipe matches: 3 wood → wooden_axe (workbench
	# mode unlocks tools that hand mode doesn't).
	var inv: Object = p.player().inventory
	inv.add_to_bag({"id": "wood", "category": "material", "count": 3}, 32)
	cui._grid = [
		{"id": "wood", "category": "material", "count": 1},
		{"id": "wood", "category": "material", "count": 1},
		{"id": "wood", "category": "material", "count": 1},
		{}, {}, {}, {}, {}, {},
	]
	cui.call("_update_match")
	var matched: Dictionary = cui._matched
	p.check(str(matched.get("id", "")) == "wooden_axe",
		"workbench mode should match wooden_axe for 3-wood grid, matched %s" % matched.get("id", "<none>"))

	cui.call("hide_ui")
	await p.wait_frames(2)

	# -----------------------------------------------------------------------
	# (iii) Pressing E does nothing crafting-related (or aliases C — either is
	# acceptable per the spec, but we assert it doesn't open a stale
	# workbench-only flow that bypasses the unified path). The minimal
	# correct behaviour: E either does nothing or opens the same unified UI.
	# -----------------------------------------------------------------------
	# Move far from the workbench so a "stale workbench-only open" would be
	# visibly wrong — workbench_mode would be true with no workbench nearby.
	p.teleport(player_tile + Vector2i(8, 8))
	await p.wait_frames(3)

	var ev_e := InputEventKey.new()
	ev_e.pressed = true
	ev_e.keycode = KEY_E
	p.player()._unhandled_input(ev_e)
	await p.wait_frames(3)

	# Either: UI is closed (E unbound); or: UI is open but _workbench_mode
	# matches proximity (i.e. false here, since we walked away).
	if bool(cui.visible):
		p.check(not bool(cui._workbench_mode),
			"E key opened CraftingUI in workbench mode while far from any workbench — " +
			"E is still routing through the legacy open_workbench() path that ignores proximity")
	# Either outcome is OK — the spec lets E be a no-op or alias.

	p.pass_scenario("KEY_C unified-opens crafting; workbench mode auto-detected by proximity")

func _press_c(p: Node) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_C
	p.player()._unhandled_input(ev)

func _player_tile(p: Node) -> Vector2i:
	return Vector2i(
		int(floor(p.player().position.x / Constants.TILE_SIZE)),
		int(floor(p.player().position.y / Constants.TILE_SIZE)))
