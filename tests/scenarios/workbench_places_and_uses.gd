## Scenario: placing a workbench tile via the bus stores atlas (1,2) on the
## object layer, and walking adjacent + pressing E opens the CraftingUI in
## workbench mode.
##
## Regression target: workbench was crafted but right-clicking produced
## "Player: no structure handler for workbench" because TileRegistry,
## StructureRegistry, and Player._place_structure all lacked a workbench
## entry — three missing wirings the other structures (campfire, bedroll,
## tether, shrine) all had.
##
## Run:
##   godot4 --headless --path . -- --puppet-scenario=res://tests/scenarios/workbench_places_and_uses.gd
extends Node

const WORKBENCH_ATLAS := Vector2i(1, 2)

func _run(p: Node) -> void:
	await p.wait_ready()
	await p.wait_frames(5)

	var world: Node = p.world()
	var bus: Node = world.get_node_or_null("TileMutationBus")
	p.check(bus != null, "World has no TileMutationBus")

	# Tile near the player so its chunk is loaded. Offset (3,0) keeps it
	# clear of starter tiles other scenarios may have placed.
	var tile := Vector2i(
		int(floor(p.player().position.x / Constants.TILE_SIZE)),
		int(floor(p.player().position.y / Constants.TILE_SIZE))) + Vector2i(3, 0)
	if p.has_object_at(tile):
		bus.request_remove_tile(tile, 1)
		await p.wait_frames(2)

	bus.request_place_tile(tile, 1, "workbench")
	await p.wait_frames(3)

	# Step 1: the CRDT has the tile at the workbench atlas coord.
	p.check(p.object_atlas_at(tile) == WORKBENCH_ATLAS,
		"workbench atlas missing at %s after place (got %s) — TileRegistry likely missing a 'workbench' entry" \
			% [tile, p.object_atlas_at(tile)])

	# Step 2: a Workbench scene exists on the chunk (mirrors the campfire/bedroll check).
	var workbench_scene: Node = _find_structure_at(world, tile, "Workbench.gd")
	p.check(workbench_scene != null,
		"no Workbench scene spawned at %s — StructureRegistry likely missing the (1,2) → Workbench.gd mapping" % tile)

	# Step 3: the CraftingSystem (list-style overlay) exists and starts closed.
	# Note: CraftingUI (the grid-style overlay) is intentionally not asserted
	# on here anymore — KEY_E routes to CraftingSystem since the C/E wiring
	# was inverted (the user prefers the list overlay to the 2×2/3×3 grid).
	var cs: Node = world.get_node_or_null("CraftingSystem")
	p.check(cs != null, "World has no CraftingSystem sibling node")
	p.check(not bool(cs.is_open), "sanity: CraftingSystem should start closed")

	# Step 4: stand the player adjacent to the workbench (within the 2-tile
	# WORKBENCH_RANGE used by Player.is_near_workbench) and press E. Inventory
	# needs at least one affordable recipe or open_menu() bails with
	# "No recipes known" without flipping is_open.
	var inv0: Object = p.player().inventory
	inv0.add_to_bag({"id": "wood", "category": "material", "count": 6}, 32)
	p.teleport(tile + Vector2i(-1, 0))
	await p.wait_frames(2)

	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_E
	p.player()._unhandled_input(ev)
	await p.wait_frames(3)

	# Step 5: CraftingSystem is now open and showing workbench recipes
	# (wooden_axe, requires_workbench=true) because we are in WORKBENCH_RANGE.
	p.check(bool(cs.is_open), "CraftingSystem should be open after pressing E next to workbench")
	var has_workbench_recipe := false
	for recipe in cs._display_recipes:
		var out: Dictionary = (recipe as Dictionary).get("output", {}) as Dictionary
		if str(out.get("id", "")) == "wooden_axe":
			has_workbench_recipe = true
			break
	p.check(has_workbench_recipe,
		"CraftingSystem next to workbench should include wooden_axe in _display_recipes — workbench-mode pass-through broken")
	cs.close_menu()
	await p.wait_frames(1)

	# Step 6 (the real "no structure handler" regression): drive the placement
	# path Player uses when the player right-clicks while holding a workbench.
	# Pre-fix this dropped through to "Player: no structure handler for
	# workbench" and never called the bus.
	var inv: Object = p.player().inventory
	inv.add_to_bag({"id": "workbench", "category": "structure", "count": 1}, 1)
	var place_tile := tile + Vector2i(0, 2)
	if p.has_object_at(place_tile):
		bus.request_remove_tile(place_tile, 1)
		await p.wait_frames(2)
	# Position player one tile west of the target, facing east.
	p.teleport(place_tile + Vector2i(-1, 0))
	p.player()._facing = Vector2(1, 0)
	await p.wait_frames(1)
	p.player().call("_place_structure", "workbench")
	await p.wait_frames(3)

	p.check(p.object_atlas_at(place_tile) == WORKBENCH_ATLAS,
		"_place_structure('workbench') should have placed atlas (1,2) at %s (got %s) — Player.gd likely missing 'workbench' from its placement whitelist" \
			% [place_tile, p.object_atlas_at(place_tile)])
	p.check(inv.bag_stack_total("workbench") == 0,
		"workbench should have been consumed from the bag after _place_structure")

	p.pass_scenario("workbench tile places via bus, scene spawns, E opens CraftingSystem in workbench mode, _place_structure handles 'workbench'")

## Walk the chunk children looking for a node whose script path ends with the
## given suffix and whose world_tile_pos matches.
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
