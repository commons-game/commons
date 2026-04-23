## print_tech_tree.gd — headless script that prints the full crafting tech tree.
##
## Run with:
##   ~/bin/godot4 --headless --path /home/adam/development/commons \
##       -s scripts/print_tech_tree.gd
##
## Output is grouped by tier (hand / workbench) and category (structure / tool).
extends SceneTree

const RecipeRegistryScript := preload("res://autoloads/RecipeRegistry.gd")

func _init() -> void:
	var reg := RecipeRegistryScript.new()
	reg._ready()

	var hand_recipes:      Array = []
	var workbench_recipes: Array = []

	for recipe in reg.all_recipes():
		if bool(recipe.get("requires_workbench", false)):
			workbench_recipes.append(recipe)
		else:
			hand_recipes.append(recipe)

	print("")
	print("═══════════════════════════════════════")
	print("  COMMONS TECH TREE")
	print("═══════════════════════════════════════")

	print("")
	print("── HAND CRAFTING ──────────────────────")
	_print_group(hand_recipes)

	print("")
	print("── WORKBENCH ──────────────────────────")
	_print_group(workbench_recipes)

	print("")
	reg.free()
	quit()

func _print_group(recipes: Array) -> void:
	if recipes.is_empty():
		print("  (none)")
		return

	# Group by output category
	var by_category: Dictionary = {}
	for recipe in recipes:
		var cat: String = str((recipe["output"] as Dictionary).get("category", "misc"))
		if not by_category.has(cat):
			by_category[cat] = []
		by_category[cat].append(recipe)

	for cat in by_category:
		print("  [%s]" % cat.to_upper())
		for recipe in by_category[cat]:
			var output: Dictionary = recipe["output"] as Dictionary
			var inputs: Dictionary = recipe["inputs"] as Dictionary
			var out_id:    String  = str(output.get("id", "?"))
			var out_count: int     = int(output.get("count", 1))

			# Format inputs: "3×wood + 2×stone"
			var parts: Array = []
			for ing in inputs:
				parts.append("%d×%s" % [int(inputs[ing]), ing])
			var ing_str: String = " + ".join(parts)

			var count_str: String = " (×%d)" % out_count if out_count > 1 else ""
			print("    %-20s ← %s%s" % [out_id, ing_str, count_str])
		print("")
