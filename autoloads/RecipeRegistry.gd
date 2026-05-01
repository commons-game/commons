## RecipeRegistry — maps ingredient sets to crafted outputs.
##
## Shapeless recipes: ingredient counts must match exactly (order irrelevant).
## The 2x2 crafting grid produces a {item_id: count} dict; match_recipe() looks
## up what that combination yields.
##
## Usage:
##   RecipeRegistry.match_recipe({"wood": 4})
##   # → {"id": "campfire", "category": "structure", "count": 1}
##
##   RecipeRegistry.match_recipe({"wood": 3}, true)
##   # → {"id": "wooden_axe", "category": "tool", "count": 1}  (workbench mode)
##
##   RecipeRegistry.match_recipe({"stone": 1})
##   # → {}  (no recipe)
##
## Recipes with requires_workbench=true only match when workbench_mode=true.
##
## Mods can call RecipeRegistry.register() in their _ready() to add recipes.
extends Node

## Each entry: { inputs: {id: count}, output: {id, category, count},
##               requires_workbench: bool }
var _recipes: Array = []

func _ready() -> void:
	_register_builtins()

## Register a shapeless recipe.
## inputs:             Dictionary mapping item_id → required count
## output:             ItemStack dict { id, category, count }
## requires_workbench: if true, only matches when workbench_mode=true
func register(inputs: Dictionary, output: Dictionary,
		requires_workbench: bool = false) -> void:
	_recipes.append({
		"inputs": inputs.duplicate(),
		"output": output.duplicate(),
		"requires_workbench": requires_workbench,
	})

## Given a dict of {item_id: count} from the crafting grid, return the
## matching recipe output as an ItemStack dict, or {} if no recipe matches.
## workbench_mode: pass true when the player is standing at a workbench.
##
## Priority: when workbench_mode=true, workbench-required recipes take priority
## over hand recipes with the same ingredient set. This means 3 wood at a
## workbench yields wooden_axe (not campfire).
func match_recipe(items: Dictionary, workbench_mode: bool = false) -> Dictionary:
	var clean: Dictionary = {}
	for k in items:
		if int(items[k]) > 0:
			clean[k] = int(items[k])
	if clean.is_empty():
		return {}
	# Pass 1 (workbench mode only): workbench-required recipes have priority.
	if workbench_mode:
		for recipe in _recipes:
			if not bool(recipe.get("requires_workbench", false)):
				continue
			if _dicts_equal(clean, recipe["inputs"] as Dictionary):
				return (recipe["output"] as Dictionary).duplicate()
	# Pass 2: hand recipes (requires_workbench=false).
	for recipe in _recipes:
		if bool(recipe.get("requires_workbench", false)):
			continue
		if _dicts_equal(clean, recipe["inputs"] as Dictionary):
			return (recipe["output"] as Dictionary).duplicate()
	return {}

## Returns all registered recipes (read-only copy). Used by CraftingSystem to
## list known recipes the player could work toward.
func all_recipes() -> Array:
	return _recipes.duplicate()

func _dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or int(b[k]) != int(a[k]):
			return false
	return true

func _register_builtins() -> void:
	# Hand-craftable structures (no workbench required)
	register({"wood": 3}, {"id": "campfire",  "category": "structure", "count": 1})
	register({"wood": 4}, {"id": "bedroll",   "category": "structure", "count": 1})
	register({"wood": 6}, {"id": "workbench", "category": "structure", "count": 1})

	# Flint tool — hand-craftable
	register({"stone": 2, "wood": 2}, {"id": "flint_knife", "category": "tool", "count": 1})

	# Tether — requires Marrow (from Wisp night mob) + Moonstone (harvested in Hollow at night).
	# Both materials are night-gated, making the Tether require engaging with the dark.
	register({"marrow": 1, "moonstone": 1}, {"id": "tether", "category": "structure", "count": 1})

	# Shrine — territory anchor. Requires late-game materials.
	# Hand-craftable (no workbench) since it is a progression keystone.
	register({"mass_core": 1, "form_crystal": 1, "ichor": 1, "cipher": 1},
	         {"id": "shrine", "category": "structure", "count": 1})

	# Workbench-required tools
	register({"wood": 3},             {"id": "wooden_axe",      "category": "tool", "count": 1}, true)
	register({"wood": 2, "stone": 1}, {"id": "wooden_pickaxe",  "category": "tool", "count": 1}, true)
	register({"stone": 3, "wood": 2}, {"id": "stone_axe",       "category": "tool", "count": 1}, true)
	register({"stone": 2, "wood": 3}, {"id": "stone_pickaxe",   "category": "tool", "count": 1}, true)
