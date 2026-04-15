## Tests for RecipeRegistry — shapeless recipe matching.
##
## Uses the autoload singleton directly so tests cover the actual registered
## recipes, not an isolated copy. Custom recipes are registered on a fresh
## instance to avoid polluting the singleton.
extends GdUnitTestSuite

const RecipeRegistryScript := preload("res://autoloads/RecipeRegistry.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Returns a fresh RecipeRegistry with builtins registered (isolated from singleton).
func _make() -> Object:
	var r := RecipeRegistryScript.new()
	add_child(r)
	return r

func after_test() -> void:
	# queue_free any children added during the test
	for child in get_children():
		if child is RecipeRegistryScript:
			child.queue_free()

# ---------------------------------------------------------------------------
# Hand-craftable structures — campfire and workbench (no workbench required)
# ---------------------------------------------------------------------------

func test_four_wood_yields_campfire() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"wood": 4})
	assert_str(str(out.get("id", ""))).is_equal("campfire")

func test_campfire_is_structure_category() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"wood": 4})
	assert_str(str(out.get("category", ""))).is_equal("structure")

func test_campfire_count_is_1() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"wood": 4})
	assert_int(int(out.get("count", 0))).is_equal(1)

func test_six_wood_yields_workbench() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"wood": 6})
	assert_str(str(out.get("id", ""))).is_equal("workbench")

func test_workbench_is_structure_category() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"wood": 6})
	assert_str(str(out.get("category", ""))).is_equal("structure")

# ---------------------------------------------------------------------------
# Workbench-required tools — only match with workbench_mode=true
# ---------------------------------------------------------------------------

func test_wooden_axe_requires_workbench_false_mode() -> void:
	var r = _make()
	# Without workbench mode, wooden_axe should NOT be crafted
	var out: Dictionary = r.match_recipe({"wood": 3})
	assert_bool(out.is_empty()).is_true()

func test_wooden_axe_matches_in_workbench_mode() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"wood": 3}, true)
	assert_str(str(out.get("id", ""))).is_equal("wooden_axe")

func test_wooden_axe_is_tool_category() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"wood": 3}, true)
	assert_str(str(out.get("category", ""))).is_equal("tool")

func test_wooden_axe_count_is_1() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"wood": 3}, true)
	assert_int(int(out.get("count", 0))).is_equal(1)

func test_wooden_pickaxe_requires_workbench() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"wood": 2, "stone": 1})
	assert_bool(out.is_empty()).is_true()

func test_wooden_pickaxe_matches_in_workbench_mode() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"wood": 2, "stone": 1}, true)
	assert_str(str(out.get("id", ""))).is_equal("wooden_pickaxe")

func test_wooden_pickaxe_order_independence() -> void:
	# Dict order should not matter
	var r = _make()
	var out: Dictionary = r.match_recipe({"stone": 1, "wood": 2}, true)
	assert_str(str(out.get("id", ""))).is_equal("wooden_pickaxe")

# ---------------------------------------------------------------------------
# Stone tools — workbench required
# ---------------------------------------------------------------------------

func test_stone_axe_requires_workbench() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"stone": 3, "wood": 2})
	assert_bool(out.is_empty()).is_true()

func test_stone_axe_matches_in_workbench_mode() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"stone": 3, "wood": 2}, true)
	assert_str(str(out.get("id", ""))).is_equal("stone_axe")

func test_stone_axe_is_tool_category() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"stone": 3, "wood": 2}, true)
	assert_str(str(out.get("category", ""))).is_equal("tool")

func test_stone_pickaxe_matches_in_workbench_mode() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"stone": 2, "wood": 3}, true)
	assert_str(str(out.get("id", ""))).is_equal("stone_pickaxe")

func test_stone_pickaxe_is_tool_category() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"stone": 2, "wood": 3}, true)
	assert_str(str(out.get("category", ""))).is_equal("tool")

func test_stone_axe_and_pickaxe_are_distinct_recipes() -> void:
	var r = _make()
	var axe: Dictionary = r.match_recipe({"stone": 3, "wood": 2}, true)
	var pick: Dictionary = r.match_recipe({"stone": 2, "wood": 3}, true)
	assert_str(str(axe.get("id", ""))).is_equal("stone_axe")
	assert_str(str(pick.get("id", ""))).is_equal("stone_pickaxe")

# ---------------------------------------------------------------------------
# No-match cases
# ---------------------------------------------------------------------------

func test_empty_input_returns_empty() -> void:
	var r = _make()
	assert_bool(r.match_recipe({}).is_empty()).is_true()

func test_wrong_count_no_match() -> void:
	var r = _make()
	# 5 wood is not a recipe
	assert_bool(r.match_recipe({"wood": 5}).is_empty()).is_true()

func test_too_few_wood_no_match() -> void:
	var r = _make()
	assert_bool(r.match_recipe({"wood": 2}).is_empty()).is_true()

func test_extra_ingredient_no_match() -> void:
	var r = _make()
	# 4 wood + 1 stone is not a recipe
	assert_bool(r.match_recipe({"wood": 4, "stone": 1}).is_empty()).is_true()

func test_unknown_ingredient_no_match() -> void:
	var r = _make()
	assert_bool(r.match_recipe({"unicorn_dust": 1}).is_empty()).is_true()

func test_single_stone_no_match() -> void:
	var r = _make()
	assert_bool(r.match_recipe({"stone": 1}).is_empty()).is_true()

# ---------------------------------------------------------------------------
# workbench_mode does not grant hand-craft recipes unexpectedly
# ---------------------------------------------------------------------------

func test_campfire_also_available_in_workbench_mode() -> void:
	# Hand-craft recipes are always available, even in workbench mode.
	var r = _make()
	var out: Dictionary = r.match_recipe({"wood": 4}, true)
	assert_str(str(out.get("id", ""))).is_equal("campfire")

func test_workbench_structure_also_available_in_workbench_mode() -> void:
	var r = _make()
	var out: Dictionary = r.match_recipe({"wood": 6}, true)
	assert_str(str(out.get("id", ""))).is_equal("workbench")

# ---------------------------------------------------------------------------
# Custom registration
# ---------------------------------------------------------------------------

func test_custom_recipe_registered_and_matched() -> void:
	var r = _make()
	r.register({"stone": 5}, {"id": "stone_wall", "category": "material", "count": 1})
	var out: Dictionary = r.match_recipe({"stone": 5})
	assert_str(str(out.get("id", ""))).is_equal("stone_wall")

func test_custom_workbench_recipe_registered_and_matched() -> void:
	var r = _make()
	r.register({"stone": 5}, {"id": "stone_wall", "category": "material", "count": 1}, true)
	# Without workbench mode: no match
	assert_bool(r.match_recipe({"stone": 5}).is_empty()).is_true()
	# With workbench mode: matches
	var out: Dictionary = r.match_recipe({"stone": 5}, true)
	assert_str(str(out.get("id", ""))).is_equal("stone_wall")

func test_all_recipes_returns_nonempty_array() -> void:
	var r = _make()
	assert_int(r.all_recipes().size()).is_greater(0)

func test_all_recipes_count_grows_after_register() -> void:
	var r = _make()
	var count_before: int = r.all_recipes().size()
	r.register({"stone": 3}, {"id": "stone_wall", "category": "material", "count": 1})
	assert_int(r.all_recipes().size()).is_equal(count_before + 1)

# ---------------------------------------------------------------------------
# Output is a copy (mutations don't affect registry)
# ---------------------------------------------------------------------------

func test_match_returns_independent_copy() -> void:
	var r = _make()
	var out1: Dictionary = r.match_recipe({"wood": 4})
	out1["id"] = "tampered"
	var out2: Dictionary = r.match_recipe({"wood": 4})
	assert_str(str(out2.get("id", ""))).is_equal("campfire")
