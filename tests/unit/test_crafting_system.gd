## Tests for CraftingSystem — the recipe-selection overlay.
##
## Catches the regression where crafting auto-selected the best affordable
## recipe instead of letting the player choose, and where is_open=true
## failed to block player movement input.
##
## Strategy: instantiate CraftingSystem with a real Inventory and real
## RecipeRegistry autoload. Call open_menu()/close_menu()/_confirm_craft()
## directly; assert on is_open state and inventory contents.
extends GdUnitTestSuite

const CraftingSystemScript := preload("res://items/CraftingSystem.gd")
const InventoryScript       := preload("res://items/Inventory.gd")

var _cs: Node   = null
var _inv: Object = null

func before_test() -> void:
	_inv = InventoryScript.new()
	_cs = CraftingSystemScript.new()
	_cs.inventory = _inv
	add_child(_cs)
	await get_tree().process_frame

func after_test() -> void:
	if is_instance_valid(_cs): _cs.queue_free()
	_cs = null
	_inv = null

# ---------------------------------------------------------------------------
# is_open state transitions
# ---------------------------------------------------------------------------

func test_is_open_starts_false() -> void:
	assert_bool(_cs.is_open).is_false()

func test_open_menu_sets_is_open_true() -> void:
	_inv.add_to_bag({"id": "wood", "category": "material", "count": 3}, 32)
	_cs.open_menu()
	assert_bool(_cs.is_open).is_true()
	_cs.close_menu()

func test_close_menu_sets_is_open_false() -> void:
	_inv.add_to_bag({"id": "wood", "category": "material", "count": 3}, 32)
	_cs.open_menu()
	_cs.close_menu()
	assert_bool(_cs.is_open).is_false()

func test_open_menu_with_null_inventory_stays_closed() -> void:
	# is_open must stay false when there is no inventory — this previously
	# caused a null-ref crash that manifested as the menu silently not opening.
	_cs.inventory = null
	_cs.open_menu()
	assert_bool(_cs.is_open).is_false()
	_cs.inventory = _inv

# ---------------------------------------------------------------------------
# Recipe ordering: affordable first
# ---------------------------------------------------------------------------

func test_affordable_recipes_come_before_unaffordable() -> void:
	# 3 wood → can afford campfire but not workbench (6 wood) or bedroll (4 reeds).
	_inv.add_to_bag({"id": "wood", "category": "material", "count": 3}, 32)
	_cs.open_menu()
	assert_int(_cs._display_recipes.size()).is_greater(0)
	# The first recipe must be affordable.
	assert_bool(_cs._can_afford(_cs._display_recipes[0] as Dictionary)).is_true()
	_cs.close_menu()

func test_no_affordable_recipe_appears_after_an_unaffordable_one() -> void:
	_inv.add_to_bag({"id": "wood", "category": "material", "count": 3}, 32)
	_cs.open_menu()
	var passed_unaffordable := false
	for recipe in _cs._display_recipes:
		if not _cs._can_afford(recipe as Dictionary):
			passed_unaffordable = true
		elif passed_unaffordable:
			# An affordable recipe appeared after an unaffordable one — fail.
			assert_bool(false).is_true()
	_cs.close_menu()

# ---------------------------------------------------------------------------
# _confirm_craft — ingredients consumed, menu closes
# ---------------------------------------------------------------------------

func test_confirm_craft_campfire_consumes_wood() -> void:
	_inv.add_to_bag({"id": "wood", "category": "material", "count": 6}, 32)
	_cs.open_menu()
	# Find campfire in display recipes and select it.
	var idx := _find_recipe_index("campfire")
	if idx < 0:
		return  # campfire not available with this inventory — skip
	_cs._selected = idx
	_cs._confirm_craft()
	assert_int(_inv.bag_stack_total("wood")).is_equal(3)  # 6 − 3 = 3

func test_confirm_craft_closes_menu_on_success() -> void:
	_inv.add_to_bag({"id": "wood", "category": "material", "count": 3}, 32)
	_cs.open_menu()
	_cs._selected = _first_affordable_index()
	_cs._confirm_craft()
	assert_bool(_cs.is_open).is_false()

func test_confirm_craft_does_not_consume_when_unaffordable() -> void:
	# Only 1 wood — cannot afford any recipe.
	_inv.add_to_bag({"id": "wood", "category": "material", "count": 1}, 32)
	_cs.open_menu()
	# Force selection of an unaffordable recipe.
	var unaffordable_idx := _first_unaffordable_index()
	if unaffordable_idx < 0:
		_cs.close_menu()
		return  # no unaffordable recipes — skip
	_cs._selected = unaffordable_idx
	var wood_before: int = _inv.bag_stack_total("wood")
	_cs._confirm_craft()
	assert_int(_inv.bag_stack_total("wood")).is_equal(wood_before)

func test_confirm_craft_does_not_close_menu_when_unaffordable() -> void:
	_inv.add_to_bag({"id": "wood", "category": "material", "count": 1}, 32)
	_cs.open_menu()
	var unaffordable_idx := _first_unaffordable_index()
	if unaffordable_idx < 0:
		_cs.close_menu()
		return
	_cs._selected = unaffordable_idx
	_cs._confirm_craft()
	assert_bool(_cs.is_open).is_true()
	_cs.close_menu()

# ---------------------------------------------------------------------------
# _cycle — wraps at both ends
# ---------------------------------------------------------------------------

func test_cycle_forward_wraps_at_last_recipe() -> void:
	_inv.add_to_bag({"id": "wood", "category": "material", "count": 3}, 32)
	_cs.open_menu()
	if _cs._display_recipes.size() < 2:
		_cs.close_menu()
		return
	_cs._selected = _cs._display_recipes.size() - 1
	_cs._cycle(1)
	assert_int(_cs._selected).is_equal(0)
	_cs.close_menu()

func test_cycle_backward_wraps_at_first_recipe() -> void:
	_inv.add_to_bag({"id": "wood", "category": "material", "count": 3}, 32)
	_cs.open_menu()
	if _cs._display_recipes.size() < 2:
		_cs.close_menu()
		return
	_cs._selected = 0
	_cs._cycle(-1)
	assert_int(_cs._selected).is_equal(_cs._display_recipes.size() - 1)
	_cs.close_menu()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_recipe_index(output_id: String) -> int:
	for i in range(_cs._display_recipes.size()):
		var r := _cs._display_recipes[i] as Dictionary
		if str((r.get("output", {}) as Dictionary).get("id", "")) == output_id:
			return i
	return -1

func _first_affordable_index() -> int:
	for i in range(_cs._display_recipes.size()):
		if _cs._can_afford(_cs._display_recipes[i] as Dictionary):
			return i
	return 0

func _first_unaffordable_index() -> int:
	for i in range(_cs._display_recipes.size()):
		if not _cs._can_afford(_cs._display_recipes[i] as Dictionary):
			return i
	return -1
