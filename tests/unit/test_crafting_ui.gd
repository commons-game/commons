## Tests for CraftingUI logic — slot cycling, recipe matching gate, crafting output.
##
## Strategy: instantiate CraftingUI, set a real Inventory, call internal methods
## directly. The UI builds itself in _ready() (adds Panel/Button nodes) which is
## harmless in the test tree.
##
## What is covered:
##   - _cycle_slot(): empty→first-material→next→clear
##   - _update_match(): grid items forwarded correctly to RecipeRegistry
##   - _check_can_craft(): gates on bag contents
##   - _do_craft(): consumes ingredients, auto-equips tools, falls back to bag
##   - open_workbench(): switches to 3×3 grid, unlocks workbench recipes
extends GdUnitTestSuite

const CraftingUIScript := preload("res://ui/CraftingUI.gd")
const InventoryScript  := preload("res://items/Inventory.gd")

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

var _cui: Node   = null
var _inv: Object = null

func before_test() -> void:
	_inv = InventoryScript.new()
	_cui = CraftingUIScript.new()
	add_child(_cui)
	await get_tree().process_frame
	_cui.inventory = _inv

func after_test() -> void:
	if is_instance_valid(_cui): _cui.queue_free()
	_cui = null
	_inv = null

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _add_wood(n: int) -> void:
	_inv.add_to_bag({"id": "wood", "category": "material", "count": n}, 32)

func _add_stone(n: int) -> void:
	_inv.add_to_bag({"id": "stone", "category": "material", "count": n}, 32)

func _set_grid(items: Array) -> void:
	# items: Array of String ids (or "" for empty). Length must match grid size.
	_cui._grid = []
	for i in range(items.size()):
		var id: String = items[i] if i < items.size() else ""
		if id == "":
			_cui._grid.append({})
		else:
			_cui._grid.append({"id": id, "category": "material", "count": 1})

func _set_grid_4(items: Array) -> void:
	# Convenience for 2x2 grid (4 slots)
	_set_grid(items)

# ---------------------------------------------------------------------------
# _cycle_slot — slot cycling through bag materials
# ---------------------------------------------------------------------------

func test_cycle_empty_slot_with_wood_fills_wood() -> void:
	_add_wood(3)
	_cui._cycle_slot(0)
	assert_str(str((_cui._grid[0] as Dictionary).get("id", ""))).is_equal("wood")

func test_cycle_filled_slot_advances_to_next_material() -> void:
	_add_wood(3)
	_add_stone(1)
	# Pre-fill slot 0 with wood
	_cui._grid[0] = {"id": "wood", "category": "material", "count": 1}
	_cui._cycle_slot(0)
	assert_str(str((_cui._grid[0] as Dictionary).get("id", ""))).is_equal("stone")

func test_cycle_last_material_clears_slot() -> void:
	_add_wood(3)
	# Only wood in bag — cycling wood should clear the slot
	_cui._grid[0] = {"id": "wood", "category": "material", "count": 1}
	_cui._cycle_slot(0)
	assert_bool((_cui._grid[0] as Dictionary).is_empty()).is_true()

func test_cycle_empty_bag_leaves_slot_empty() -> void:
	_cui._cycle_slot(0)
	assert_bool((_cui._grid[0] as Dictionary).is_empty()).is_true()

func test_cycle_only_counts_materials_not_tools() -> void:
	# Tool in bag should not appear as a cycleable option
	_inv.add_to_bag({"id": "shovel", "category": "tool", "count": 1}, 1)
	_cui._cycle_slot(0)
	assert_bool((_cui._grid[0] as Dictionary).is_empty()).is_true()

# ---------------------------------------------------------------------------
# _update_match — recipe matching (hand-craft mode, no workbench)
# ---------------------------------------------------------------------------

func test_three_wood_in_grid_matches_campfire() -> void:
	_add_wood(3)
	_set_grid_4(["wood", "wood", "wood", ""])
	_cui._update_match()
	assert_str(str((_cui._matched as Dictionary).get("id", ""))).is_equal("campfire")

func test_three_wood_without_workbench_yields_campfire_not_axe() -> void:
	# In hand mode, 3 wood → campfire (not wooden_axe, which is workbench-only).
	_add_wood(3)
	_set_grid_4(["wood", "wood", "wood", ""])
	_cui._update_match()
	assert_str(str((_cui._matched as Dictionary).get("id", ""))).is_not_equal("wooden_axe")

func test_empty_grid_no_match() -> void:
	_cui._update_match()
	assert_bool((_cui._matched as Dictionary).is_empty()).is_true()

func test_unknown_combo_no_match() -> void:
	_add_stone(4)
	_set_grid_4(["stone", "stone", "stone", "stone"])
	_cui._update_match()
	assert_bool((_cui._matched as Dictionary).is_empty()).is_true()

# ---------------------------------------------------------------------------
# Workbench mode — recipe matching
# ---------------------------------------------------------------------------

func test_open_workbench_switches_to_9_slots() -> void:
	_cui.open_workbench()
	await get_tree().process_frame
	assert_int(_cui._grid.size()).is_equal(9)

func test_open_workbench_sets_workbench_mode_flag() -> void:
	_cui.open_workbench()
	await get_tree().process_frame
	assert_bool(_cui._workbench_mode).is_true()

func test_toggle_resets_to_normal_mode() -> void:
	_cui.open_workbench()
	await get_tree().process_frame
	_cui.toggle()  # close
	_cui.toggle()  # open normal
	await get_tree().process_frame
	assert_bool(_cui._workbench_mode).is_false()
	assert_int(_cui._grid.size()).is_equal(4)

func test_workbench_mode_matches_wooden_axe() -> void:
	_add_wood(3)
	_cui.open_workbench()
	await get_tree().process_frame
	_set_grid(["wood", "wood", "wood", "", "", "", "", "", ""])
	_cui._update_match()
	assert_str(str((_cui._matched as Dictionary).get("id", ""))).is_equal("wooden_axe")

func test_workbench_mode_matches_stone_axe() -> void:
	_add_stone(3)
	_add_wood(2)
	_cui.open_workbench()
	await get_tree().process_frame
	_set_grid(["stone", "stone", "stone", "wood", "wood", "", "", "", ""])
	_cui._update_match()
	assert_str(str((_cui._matched as Dictionary).get("id", ""))).is_equal("stone_axe")

func test_workbench_mode_matches_stone_pickaxe() -> void:
	_add_stone(2)
	_add_wood(3)
	_cui.open_workbench()
	await get_tree().process_frame
	_set_grid(["stone", "stone", "wood", "wood", "wood", "", "", "", ""])
	_cui._update_match()
	assert_str(str((_cui._matched as Dictionary).get("id", ""))).is_equal("stone_pickaxe")

func test_workbench_mode_still_matches_bedroll() -> void:
	# 4 wood → bedroll in both hand and workbench mode (no workbench recipe uses 4 wood).
	_add_wood(4)
	_cui.open_workbench()
	await get_tree().process_frame
	_set_grid(["wood", "wood", "wood", "wood", "", "", "", "", ""])
	_cui._update_match()
	assert_str(str((_cui._matched as Dictionary).get("id", ""))).is_equal("bedroll")

# ---------------------------------------------------------------------------
# _check_can_craft — ingredient gating
# ---------------------------------------------------------------------------

func test_can_craft_false_when_bag_empty() -> void:
	_set_grid_4(["wood", "wood", "wood", "wood"])
	_cui._update_match()
	assert_bool(_cui._check_can_craft()).is_false()

func test_can_craft_false_when_not_enough() -> void:
	_add_wood(3)  # need 4 for campfire, only have 3
	_set_grid_4(["wood", "wood", "wood", "wood"])
	_cui._update_match()
	assert_bool(_cui._check_can_craft()).is_false()

func test_can_craft_true_when_enough_for_campfire() -> void:
	_add_wood(4)
	_set_grid_4(["wood", "wood", "wood", "wood"])
	_cui._update_match()
	assert_bool(_cui._check_can_craft()).is_true()

func test_can_craft_true_with_surplus_in_bag() -> void:
	_add_wood(10)
	_set_grid_4(["wood", "wood", "wood", "wood"])
	_cui._update_match()
	assert_bool(_cui._check_can_craft()).is_true()

func test_can_craft_false_when_no_recipe_matched() -> void:
	_add_stone(4)
	_set_grid_4(["stone", "stone", "stone", "stone"])
	_cui._update_match()
	assert_bool(_cui._check_can_craft()).is_false()

# ---------------------------------------------------------------------------
# _do_craft — ingredients consumed
# ---------------------------------------------------------------------------

func test_crafting_campfire_consumes_wood_from_bag() -> void:
	_add_wood(6)
	_set_grid_4(["wood", "wood", "wood", "wood"])
	_cui._update_match()
	_cui._can_craft = true
	_cui._do_craft()
	assert_int(_inv.bag_stack_total("wood")).is_equal(2)  # 6 - 4 = 2

func test_crafting_clears_grid() -> void:
	_add_wood(4)
	_set_grid_4(["wood", "wood", "wood", "wood"])
	_cui._update_match()
	_cui._can_craft = true
	_cui._do_craft()
	for i in range(4):
		assert_bool((_cui._grid[i] as Dictionary).is_empty()).is_true()

func test_crafting_does_nothing_when_cannot_craft() -> void:
	_add_wood(1)  # not enough
	_set_grid_4(["wood", "wood", "wood", "wood"])
	_cui._update_match()
	# _can_craft will be false — call should be a no-op
	_cui._do_craft()
	assert_int(_inv.bag_stack_total("wood")).is_equal(1)  # unchanged

# ---------------------------------------------------------------------------
# _do_craft — structure output goes to tool slot
# ---------------------------------------------------------------------------

func test_crafted_campfire_goes_to_tool_slot() -> void:
	_add_wood(3)
	_set_grid_4(["wood", "wood", "wood", ""])
	_cui._update_match()
	_cui._can_craft = true
	_cui._do_craft()
	# campfire should be in one of the tool slots
	var found := false
	for i in range(_inv.TOOL_SLOT_COUNT):
		if str((_inv.tool_slots[i] as Dictionary).get("id", "")) == "campfire":
			found = true
	assert_bool(found).is_true()

func test_crafted_campfire_not_in_bag_when_slot_available() -> void:
	_add_wood(3)
	_set_grid_4(["wood", "wood", "wood", ""])
	_cui._update_match()
	_cui._can_craft = true
	_cui._do_craft()
	assert_int(_inv.bag_stack_total("campfire")).is_equal(0)

func test_crafted_structure_goes_to_bag_when_slots_full() -> void:
	# Fill both tool slots
	_inv.set_tool_slot(0, {"id": "lantern",  "category": "tool", "count": 1})
	_inv.set_tool_slot(1, {"id": "shovel",   "category": "tool", "count": 1})
	_add_wood(3)
	_set_grid_4(["wood", "wood", "wood", ""])
	_cui._update_match()
	_cui._can_craft = true
	_cui._do_craft()
	assert_int(_inv.bag_stack_total("campfire")).is_equal(1)

# ---------------------------------------------------------------------------
# _do_craft — auto-equip tools (in workbench mode)
# ---------------------------------------------------------------------------

func test_crafted_wooden_axe_goes_to_tool_slot_in_workbench_mode() -> void:
	_add_wood(3)
	_cui.open_workbench()
	await get_tree().process_frame
	_set_grid(["wood", "wood", "wood", "", "", "", "", "", ""])
	_cui._update_match()
	_cui._can_craft = true
	_cui._do_craft()
	var found := false
	for i in range(_inv.TOOL_SLOT_COUNT):
		if str((_inv.tool_slots[i] as Dictionary).get("id", "")) == "wooden_axe":
			found = true
	assert_bool(found).is_true()

func test_crafted_tool_not_in_bag_when_slot_available() -> void:
	_add_wood(3)
	_cui.open_workbench()
	await get_tree().process_frame
	_set_grid(["wood", "wood", "wood", "", "", "", "", "", ""])
	_cui._update_match()
	_cui._can_craft = true
	_cui._do_craft()
	assert_int(_inv.bag_stack_total("wooden_axe")).is_equal(0)

func test_crafted_tool_goes_to_bag_when_all_slots_full() -> void:
	# Fill both tool slots
	_inv.set_tool_slot(0, {"id": "lantern", "category": "tool", "count": 1})
	_inv.set_tool_slot(1, {"id": "shovel",  "category": "tool", "count": 1})
	_add_wood(3)
	_cui.open_workbench()
	await get_tree().process_frame
	_set_grid(["wood", "wood", "wood", "", "", "", "", "", ""])
	_cui._update_match()
	_cui._can_craft = true
	_cui._do_craft()
	assert_int(_inv.bag_stack_total("wooden_axe")).is_equal(1)

func test_second_craft_fills_second_slot() -> void:
	# Slot 0 full, slot 1 empty — second craft should fill slot 1
	_inv.set_tool_slot(0, {"id": "lantern", "category": "tool", "count": 1})
	_add_wood(3)
	_cui.open_workbench()
	await get_tree().process_frame
	_set_grid(["wood", "wood", "wood", "", "", "", "", "", ""])
	_cui._update_match()
	_cui._can_craft = true
	_cui._do_craft()
	assert_str(str((_inv.tool_slots[1] as Dictionary).get("id", ""))).is_equal("wooden_axe")

# ---------------------------------------------------------------------------
# Stone tool crafting
# ---------------------------------------------------------------------------

func test_stone_axe_crafted_in_workbench_mode() -> void:
	_add_stone(3)
	_add_wood(2)
	_cui.open_workbench()
	await get_tree().process_frame
	_set_grid(["stone", "stone", "stone", "wood", "wood", "", "", "", ""])
	_cui._update_match()
	_cui._can_craft = true
	_cui._do_craft()
	var found := false
	for i in range(_inv.TOOL_SLOT_COUNT):
		if str((_inv.tool_slots[i] as Dictionary).get("id", "")) == "stone_axe":
			found = true
	assert_bool(found).is_true()

func test_stone_pickaxe_crafted_in_workbench_mode() -> void:
	_add_stone(2)
	_add_wood(3)
	_cui.open_workbench()
	await get_tree().process_frame
	_set_grid(["stone", "stone", "wood", "wood", "wood", "", "", "", ""])
	_cui._update_match()
	_cui._can_craft = true
	_cui._do_craft()
	var found := false
	for i in range(_inv.TOOL_SLOT_COUNT):
		if str((_inv.tool_slots[i] as Dictionary).get("id", "")) == "stone_pickaxe":
			found = true
	assert_bool(found).is_true()

func test_stone_axe_consumes_correct_ingredients() -> void:
	_add_stone(5)
	_add_wood(4)
	_cui.open_workbench()
	await get_tree().process_frame
	_set_grid(["stone", "stone", "stone", "wood", "wood", "", "", "", ""])
	_cui._update_match()
	_cui._can_craft = true
	_cui._do_craft()
	assert_int(_inv.bag_stack_total("stone")).is_equal(2)  # 5 - 3 = 2
	assert_int(_inv.bag_stack_total("wood")).is_equal(2)   # 4 - 2 = 2
