## Scenario: KEY_C (and KEY_E) routes through the list-style CraftingSystem
## (the recipe-row overlay), and that overlay auto-detects workbench mode by
## proximity at open-time so workbench recipes appear iff the player is
## standing next to a workbench.
##
## History: commit 3cab918 wired KEY_C to the grid-style CraftingUI (2×2/3×3
## ingredient grid). The user prefers the list UI. This scenario inverts the
## binding: same proximity-detection plumbing, but the list overlay is the
## consumer. The grid CraftingUI is intentionally not deleted (the user is
## deciding that separately) — it's just no longer driven by C/E.
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
	var cs: Node = world.get_node_or_null("CraftingSystem")
	p.check(cs != null, "World has no CraftingSystem")

	# -----------------------------------------------------------------------
	# (i) Far from any workbench: KEY_C opens the list overlay; the displayed
	# recipes exclude any requires_workbench=true entries (e.g. wooden_axe).
	# -----------------------------------------------------------------------
	var player_tile := _player_tile(p)
	# Clear any pre-existing workbenches in detection range (and a margin).
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var t := player_tile + Vector2i(dx, dy)
			if p.object_atlas_at(t) == WORKBENCH_ATLAS:
				bus.request_remove_tile(t, 1)
	await p.wait_frames(3)

	# Sanity: closed at start.
	if bool(cs.is_open):
		cs.close_menu()
		await p.wait_frames(1)
	p.check(not bool(cs.is_open), "sanity: CraftingSystem should be closed before C-press")

	# Inventory needs *something* affordable, otherwise open_menu shows the
	# "No recipes known" float and bails without setting is_open=true.
	var inv: Object = p.player().inventory
	inv.add_to_bag({"id": "wood", "category": "material", "count": 6}, 32)
	await p.wait_frames(1)

	_press_c(p)
	await p.wait_frames(3)

	p.check(bool(cs.is_open), "CraftingSystem should be open after pressing C")
	p.check(not _list_contains_recipe(cs, "wooden_axe"),
		"far from workbench, recipe list should EXCLUDE wooden_axe (requires_workbench=true) — proximity filter broken")
	# Sanity: at least one hand recipe (campfire) is present so we know the
	# list is populated and the wooden_axe absence above isn't vacuous.
	p.check(_list_contains_recipe(cs, "campfire"),
		"hand-mode list should still contain campfire — list isn't being populated")

	cs.close_menu()
	await p.wait_frames(2)

	# -----------------------------------------------------------------------
	# (ii) Place a workbench adjacent to the player → C now INCLUDES wooden_axe.
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

	p.check(bool(cs.is_open), "CraftingSystem should be open after pressing C near workbench")
	p.check(_list_contains_recipe(cs, "wooden_axe"),
		"adjacent to workbench, recipe list should INCLUDE wooden_axe — workbench-mode pass-through broken")

	cs.close_menu()
	await p.wait_frames(2)

	# -----------------------------------------------------------------------
	# (iii) KEY_E behaves identically to KEY_C — both go through the same
	# proximity-aware open_menu(). Still adjacent to the workbench from (ii).
	# -----------------------------------------------------------------------
	_press_e(p)
	await p.wait_frames(3)

	p.check(bool(cs.is_open), "CraftingSystem should be open after pressing E (E should alias C)")
	p.check(_list_contains_recipe(cs, "wooden_axe"),
		"E near workbench should populate workbench recipes the same as C — E is on a different code path")

	cs.close_menu()
	await p.wait_frames(2)

	# E far from workbench should also open and exclude wooden_axe.
	p.teleport(player_tile + Vector2i(8, 8))
	await p.wait_frames(3)

	_press_e(p)
	await p.wait_frames(3)

	p.check(bool(cs.is_open), "CraftingSystem should be open after pressing E far from workbench")
	p.check(not _list_contains_recipe(cs, "wooden_axe"),
		"E far from workbench should EXCLUDE wooden_axe — E is bypassing the proximity filter")

	cs.close_menu()
	await p.wait_frames(1)

	p.pass_scenario("KEY_C and KEY_E both open list-style CraftingSystem; workbench mode auto-detected by proximity")

func _press_c(p: Node) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_C
	p.player()._unhandled_input(ev)

func _press_e(p: Node) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_E
	p.player()._unhandled_input(ev)

func _player_tile(p: Node) -> Vector2i:
	return Vector2i(
		int(floor(p.player().position.x / Constants.TILE_SIZE)),
		int(floor(p.player().position.y / Constants.TILE_SIZE)))

## True iff CraftingSystem._display_recipes contains a recipe whose output id
## matches `output_id`.
func _list_contains_recipe(cs: Node, output_id: String) -> bool:
	for recipe in cs._display_recipes:
		var out: Dictionary = (recipe as Dictionary).get("output", {}) as Dictionary
		if str(out.get("id", "")) == output_id:
			return true
	return false
