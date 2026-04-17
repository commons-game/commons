## CraftingSystem — simple hand-crafting without a UI panel.
##
## Press C (or craft_key) to scan recipes in order.
## If the player has all ingredients in the bag, consume them and produce the result.
## Output goes to the active tool_slot if it's empty and the item is a tool,
## otherwise to the bag.
## Shows a brief floating label above the player that fades out.
##
## Usage (set up by World or Player):
##   var cs := CraftingSystemScript.new()
##   cs.inventory = $Player.inventory
##   cs.player_node = $Player
##   add_child(cs)
extends Node

var inventory: Object = null  # Inventory
var player_node: Node2D = null

const FLOAT_DURATION := 1.6
const FLOAT_RISE     := 24.0  # pixels to rise over duration

func try_craft() -> void:
	if inventory == null:
		push_warning("CraftingSystem: no inventory")
		return

	var recipes: Array = RecipeRegistry.all_recipes()
	for recipe in recipes:
		# Skip workbench-required recipes (this is hand crafting only)
		if bool(recipe.get("requires_workbench", false)):
			continue
		var inputs: Dictionary = recipe["inputs"] as Dictionary
		# Check all ingredients available
		var can: bool = true
		for item_id in inputs:
			if inventory.bag_stack_total(item_id) < int(inputs[item_id]):
				can = false
				break
		if not can:
			continue
		# Consume
		for item_id in inputs:
			inventory.remove_from_bag(item_id, int(inputs[item_id]))
		# Produce
		var output: Dictionary = recipe["output"] as Dictionary
		var out_id: String = str(output.get("id", ""))
		var out_cat: String = str(output.get("category", ""))
		var out_count: int = int(output.get("count", 1))
		var placed: bool = false
		# Try tool slot first for tool category
		if out_cat == "tool":
			for i in range(inventory.TOOL_SLOT_COUNT):
				var slot: Dictionary = inventory.tool_slots[i] as Dictionary
				if slot.is_empty():
					inventory.set_tool_slot(i, {"id": out_id, "category": out_cat, "count": out_count})
					placed = true
					break
		if not placed:
			inventory.add_to_bag({"id": out_id, "category": out_cat, "count": out_count},
			                     out_count if out_cat == "material" else 1)
		var display: String = str(ItemRegistry.resolve(out_id).display_name if ItemRegistry.has_item(out_id) else out_id)
		print("CraftingSystem: crafted %s" % display)
		_show_float_text("Crafted: %s" % display)
		return

	# Nothing matched
	_show_float_text("Nothing to craft")
	print("CraftingSystem: no recipe matched")

func _show_float_text(msg: String) -> void:
	if player_node == null:
		return
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	lbl.position = Vector2(-40.0, -28.0)
	player_node.add_child(lbl)

	var tween := player_node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - FLOAT_RISE, FLOAT_DURATION)
	tween.tween_property(lbl, "modulate:a", 0.0, FLOAT_DURATION)
	tween.chain().tween_callback(lbl.queue_free)
