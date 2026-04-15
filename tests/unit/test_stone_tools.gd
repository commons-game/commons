## Tests for stone tools: damage values, ItemRegistry presence, RecipeRegistry.
##
## Stone tools were added in Layer 3 alongside campfire/workbench.
## stone_axe:     3 damage vs trees (atlas 0,1), 1 vs rocks
## stone_pickaxe: 3 damage vs rocks (atlas 1,1), 1 vs trees
extends GdUnitTestSuite

const RecipeRegistryScript := preload("res://autoloads/RecipeRegistry.gd")
const ItemRegistryScript   := preload("res://items/ItemRegistry.gd")
const TileInteractionScript := preload("res://player/TileInteraction.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_recipes() -> Object:
	var r := RecipeRegistryScript.new()
	add_child(r)
	return r

func _make_items() -> Object:
	var r := ItemRegistryScript.new()
	add_child(r)
	return r

func after_test() -> void:
	for child in get_children():
		if child is RecipeRegistryScript or child is ItemRegistryScript:
			child.queue_free()

# ---------------------------------------------------------------------------
# ItemRegistry — stone tools are registered
# ---------------------------------------------------------------------------

func test_stone_axe_registered_in_item_registry() -> void:
	var r = _make_items()
	assert_bool(r.has_item("stone_axe")).is_true()

func test_stone_pickaxe_registered_in_item_registry() -> void:
	var r = _make_items()
	assert_bool(r.has_item("stone_pickaxe")).is_true()

func test_stone_axe_is_tool_category_in_registry() -> void:
	var r = _make_items()
	var d = r.resolve("stone_axe")
	assert_str(str(d.get("category") if d is Dictionary else d.category)).is_equal("tool")

func test_stone_pickaxe_is_tool_category_in_registry() -> void:
	var r = _make_items()
	var d = r.resolve("stone_pickaxe")
	assert_str(str(d.get("category") if d is Dictionary else d.category)).is_equal("tool")

# ---------------------------------------------------------------------------
# RecipeRegistry — stone tool recipes
# ---------------------------------------------------------------------------

func test_stone_axe_recipe_needs_workbench() -> void:
	var r = _make_recipes()
	assert_bool(r.match_recipe({"stone": 3, "wood": 2}).is_empty()).is_true()

func test_stone_axe_recipe_in_workbench_mode() -> void:
	var r = _make_recipes()
	var out: Dictionary = r.match_recipe({"stone": 3, "wood": 2}, true)
	assert_str(str(out.get("id", ""))).is_equal("stone_axe")

func test_stone_pickaxe_recipe_needs_workbench() -> void:
	var r = _make_recipes()
	assert_bool(r.match_recipe({"stone": 2, "wood": 3}).is_empty()).is_true()

func test_stone_pickaxe_recipe_in_workbench_mode() -> void:
	var r = _make_recipes()
	var out: Dictionary = r.match_recipe({"stone": 2, "wood": 3}, true)
	assert_str(str(out.get("id", ""))).is_equal("stone_pickaxe")

func test_stone_axe_and_pickaxe_recipes_are_distinct() -> void:
	var r = _make_recipes()
	var axe: Dictionary  = r.match_recipe({"stone": 3, "wood": 2}, true)
	var pick: Dictionary = r.match_recipe({"stone": 2, "wood": 3}, true)
	assert_str(str(axe.get("id",  ""))).is_not_equal(str(pick.get("id", "")))

# ---------------------------------------------------------------------------
# TileInteraction._tool_damage — stone tool damage values
#
# We call _tool_damage() without adding to the scene tree so @onready vars
# remain null — _tool_damage() only uses its parameters, not @onready refs.
# ---------------------------------------------------------------------------

func test_stone_axe_deals_3_vs_tree() -> void:
	var ti := TileInteractionScript.new()
	assert_int(ti._tool_damage(Vector2i(0, 1), "stone_axe")).is_equal(3)
	ti.free()

func test_stone_axe_deals_1_vs_rock() -> void:
	var ti := TileInteractionScript.new()
	assert_int(ti._tool_damage(Vector2i(1, 1), "stone_axe")).is_equal(1)
	ti.free()

func test_stone_pickaxe_deals_3_vs_rock() -> void:
	var ti := TileInteractionScript.new()
	assert_int(ti._tool_damage(Vector2i(1, 1), "stone_pickaxe")).is_equal(3)
	ti.free()

func test_stone_pickaxe_deals_1_vs_tree() -> void:
	var ti := TileInteractionScript.new()
	assert_int(ti._tool_damage(Vector2i(0, 1), "stone_pickaxe")).is_equal(1)
	ti.free()

func test_wooden_axe_still_deals_2_vs_tree() -> void:
	var ti := TileInteractionScript.new()
	assert_int(ti._tool_damage(Vector2i(0, 1), "wooden_axe")).is_equal(2)
	ti.free()

func test_wooden_pickaxe_still_deals_2_vs_rock() -> void:
	var ti := TileInteractionScript.new()
	assert_int(ti._tool_damage(Vector2i(1, 1), "wooden_pickaxe")).is_equal(2)
	ti.free()

func test_fist_deals_1_vs_tree() -> void:
	var ti := TileInteractionScript.new()
	assert_int(ti._tool_damage(Vector2i(0, 1), "")).is_equal(1)
	ti.free()

func test_fist_deals_1_vs_rock() -> void:
	var ti := TileInteractionScript.new()
	assert_int(ti._tool_damage(Vector2i(1, 1), "")).is_equal(1)
	ti.free()

# ---------------------------------------------------------------------------
# ItemRegistry — structures registered
# ---------------------------------------------------------------------------

func test_campfire_registered_in_item_registry() -> void:
	var r = _make_items()
	assert_bool(r.has_item("campfire")).is_true()

func test_workbench_registered_in_item_registry() -> void:
	var r = _make_items()
	assert_bool(r.has_item("workbench")).is_true()
