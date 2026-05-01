## CraftingSystem — recipe selection overlay for hand crafting.
##
## Press C to open the overlay. All hand-craftable recipes are listed:
##   - affordable ones first (fully opaque, yellow ► marker on selected)
##   - unaffordable ones after (modulate alpha 0.5, greyed out)
## C or Up/Down arrow cycles selection. Enter crafts. Escape closes.
##
## Usage (set up by World._setup_crafting_system):
##   var cs := CraftingSystemScript.new()
##   cs.inventory = $Player.inventory
##   cs.player_node = $Player
##   add_child(cs)
extends Node

var inventory: Object = null  # Inventory
var player_node: Node2D = null

## Public property: true while the overlay is showing.
var is_open: bool = false

const FLOAT_DURATION := 1.6
const FLOAT_RISE     := 24.0  # pixels to rise over duration

## CanvasLayer that contains the overlay panel.
var _canvas: CanvasLayer = null
## Background panel (ColorRect).
var _panel: ColorRect = null
## VBoxContainer holding one Label per recipe row.
var _vbox: VBoxContainer = null

## Ordered list of recipe dicts shown in the overlay (affordable first).
var _display_recipes: Array = []
## Index of the currently highlighted row.
var _selected: int = 0
## True iff the overlay was opened next to a workbench (auto-detected by the
## caller via Player.is_near_workbench()). Stored on the instance so a later
## _build_recipe_list() refresh keeps the same filter.
var _workbench_mode: bool = false

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Build the recipe list, show the overlay, and enter selection mode.
##
## workbench_mode: when true, recipes flagged requires_workbench=true (e.g.
## wooden_axe, stone_pickaxe) are included alongside the hand recipes. When
## false (the default), workbench recipes are filtered out. Player.gd passes
## is_near_workbench() so the same key (C or E) opens the right list based on
## proximity — replacing the legacy two-key C/E split.
func open_menu(workbench_mode: bool = false) -> void:
	if inventory == null:
		push_warning("CraftingSystem: no inventory")
		return
	_workbench_mode = workbench_mode
	_build_recipe_list()
	if _display_recipes.is_empty():
		_show_float_text("No recipes known")
		return
	is_open = true
	_selected = _first_affordable_index()
	_build_overlay()
	_refresh_overlay()

## Hide the overlay and exit selection mode.
func close_menu() -> void:
	is_open = false
	if _canvas != null:
		_canvas.queue_free()
		_canvas = null
		_panel = null
		_vbox = null

## Move selection up (-1) or down (+1).
func _cycle(direction: int) -> void:
	if _display_recipes.is_empty():
		return
	_selected = (_selected + direction + _display_recipes.size()) % _display_recipes.size()
	_refresh_overlay()

## Craft the selected recipe if affordable; close menu on success.
func _confirm_craft() -> void:
	if not is_open or _display_recipes.is_empty():
		return
	var recipe: Dictionary = _display_recipes[_selected] as Dictionary
	if not _can_afford(recipe):
		_show_float_text("Missing ingredients")
		return
	_do_craft(recipe)
	close_menu()

# ---------------------------------------------------------------------------
# Input — handled here so Player.gd can delegate cleanly
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = (event as InputEventKey).keycode
	match key:
		KEY_UP:
			_cycle(-1)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_cycle(1)
			get_viewport().set_input_as_handled()
		KEY_C:
			_cycle(1)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			_confirm_craft()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			close_menu()
			get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# Recipe helpers
# ---------------------------------------------------------------------------

func _build_recipe_list() -> void:
	_display_recipes.clear()
	var affordable: Array = []
	var unaffordable: Array = []
	for recipe in RecipeRegistry.all_recipes():
		if not _workbench_mode and bool(recipe.get("requires_workbench", false)):
			continue
		if _can_afford(recipe):
			affordable.append(recipe)
		else:
			unaffordable.append(recipe)
	_display_recipes = affordable + unaffordable

func _can_afford(recipe: Dictionary) -> bool:
	var inputs: Dictionary = recipe["inputs"] as Dictionary
	for item_id in inputs:
		if inventory.bag_stack_total(item_id) < int(inputs[item_id]):
			return false
	return true

func _first_affordable_index() -> int:
	for i in range(_display_recipes.size()):
		if _can_afford(_display_recipes[i] as Dictionary):
			return i
	return 0

func _do_craft(recipe: Dictionary) -> void:
	var inputs: Dictionary = recipe["inputs"] as Dictionary
	# Consume ingredients.
	for item_id in inputs:
		inventory.remove_from_bag(item_id, int(inputs[item_id]))
	# Produce output.
	var output: Dictionary = recipe["output"] as Dictionary
	var out_id: String = str(output.get("id", ""))
	var out_cat: String = str(output.get("category", ""))
	var out_count: int = int(output.get("count", 1))
	var placed: bool = false
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

# ---------------------------------------------------------------------------
# Overlay construction
# ---------------------------------------------------------------------------

const PANEL_WIDTH  := 340
const ROW_HEIGHT   := 22
const PADDING      := 10
const FONT_SIZE    := 14

func _build_overlay() -> void:
	# Tear down any previous overlay.
	if _canvas != null:
		_canvas.queue_free()

	_canvas = CanvasLayer.new()
	_canvas.layer = 20  # above Hotbar (11)
	# Add to world tree (parent of player_node), not to player itself,
	# so it doesn't move with the player.
	if player_node != null and player_node.get_parent() != null:
		player_node.get_parent().add_child(_canvas)
	else:
		add_child(_canvas)

	# Background panel — dark semi-transparent.
	_panel = ColorRect.new()
	_panel.color = Color(0.08, 0.08, 0.08, 0.88)
	_canvas.add_child(_panel)

	# Title label. Suffix " — WORKBENCH" when proximity opened workbench recipes.
	var title := Label.new()
	var suffix: String = "  (WORKBENCH)" if _workbench_mode else ""
	title.text = "CRAFTING%s  (C/↑↓ cycle · Enter craft · Esc close)" % suffix
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	title.position = Vector2(PADDING, PADDING)
	_panel.add_child(title)

	# VBox for rows.
	_vbox = VBoxContainer.new()
	_vbox.position = Vector2(PADDING, PADDING + 20)
	_vbox.add_theme_constant_override("separation", 2)
	_panel.add_child(_vbox)

	# Create one label per recipe.
	for i in range(_display_recipes.size()):
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", FONT_SIZE)
		lbl.custom_minimum_size = Vector2(PANEL_WIDTH - PADDING * 2, ROW_HEIGHT)
		_vbox.add_child(lbl)

	# Size panel to fit content.
	var panel_h: int = PADDING + 20 + _display_recipes.size() * (ROW_HEIGHT + 2) + PADDING
	var panel_w: int = PANEL_WIDTH
	_panel.size = Vector2(panel_w, panel_h)

	# Centre horizontally, above middle of screen.
	_panel.position = Vector2(
		(1280 - panel_w) / 2.0,
		(720 - panel_h) / 2.0 - 60.0)

func _refresh_overlay() -> void:
	if _vbox == null:
		return
	var rows: Array = _vbox.get_children()
	for i in range(rows.size()):
		if i >= _display_recipes.size():
			break
		var recipe: Dictionary = _display_recipes[i] as Dictionary
		var lbl: Label = rows[i] as Label
		var affordable: bool = _can_afford(recipe)
		var selected: bool = (i == _selected)

		# Build row text.
		var marker: String = "► " if selected else "  "
		var out: Dictionary = recipe["output"] as Dictionary
		var out_id: String = str(out.get("id", ""))
		var recipe_name: String = out_id.replace("_", " ").capitalize()
		var ingredients: String = _format_ingredients(recipe)
		lbl.text = "%s%s   %s" % [marker, recipe_name, ingredients]

		# Colour: selected = yellow; unaffordable = grey+dim.
		if selected:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.3))
		else:
			lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		lbl.modulate.a = 1.0 if affordable else 0.5

func _format_ingredients(recipe: Dictionary) -> String:
	var inputs: Dictionary = recipe["inputs"] as Dictionary
	var parts: Array = []
	for item_id in inputs:
		var need: int = int(inputs[item_id])
		var have: int = inventory.bag_stack_total(item_id) if inventory != null else 0
		parts.append("%s: %d/%d" % [item_id.replace("_", " "), have, need])
	return "(%s)" % ", ".join(parts)

# ---------------------------------------------------------------------------
# Float text (reused for feedback messages)
# ---------------------------------------------------------------------------

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
