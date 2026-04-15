## CraftingUI — shapeless crafting grid overlay.
##
## Normal mode (C key): 2×2 grid, hand-craftable recipes only.
## Workbench mode (E near workbench): 3×3 grid, workbench-required recipes unlocked.
##
## Open/close: press C in-game (Player._unhandled_input) or call open_workbench().
## Grid interaction:
##   Left-click a slot → cycles through materials in your bag (empty → wood → stone → … → empty)
##   Right-click a slot → clears it
##   Click the output slot (when lit) → craft: consumes ingredients, adds output to bag
##
## Recipe matching is live: RecipeRegistry.match_recipe() is called after every slot change.
## The output slot dims when no recipe matches or you lack the ingredients.
extends CanvasLayer

var inventory: Object = null  # Player's Inventory — set by World before show

# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------

const SLOT_SIZE   := 48
const SLOT_GAP    := 8
const PANEL_PAD   := 16
const TITLE_H     := 28

# Grid origin within the panel (relative to panel top-left)
const GRID_X := PANEL_PAD
const GRID_Y := PANEL_PAD + TITLE_H

const COLOR_BG         := Color(0.08, 0.08, 0.08, 0.92)
const COLOR_SLOT_EMPTY := Color(0.18, 0.18, 0.18, 1.0)
const COLOR_SLOT_FULL  := Color(0.28, 0.28, 0.28, 1.0)
const COLOR_OUTPUT_OFF := Color(0.18, 0.18, 0.18, 0.6)
const COLOR_OUTPUT_ON  := Color(0.20, 0.42, 0.20, 1.0)
const COLOR_CRAFT_OFF  := Color(0.25, 0.25, 0.25, 0.8)
const COLOR_CRAFT_ON   := Color(0.20, 0.65, 0.20, 1.0)
const COLOR_LABEL      := Color(0.9, 0.9, 0.8, 1.0)
const COLOR_TITLE      := Color(0.7, 0.7, 0.5, 1.0)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Grid slots — 4 in normal mode (2×2), 9 in workbench mode (3×3).
var _grid: Array = [{}, {}, {}, {}]

## Matched recipe output from RecipeRegistry, or {} if none.
var _matched: Dictionary = {}

## Whether the player currently has enough materials in the bag to craft.
var _can_craft: bool = false

## Whether we are in workbench mode (3×3 grid, unlocked recipes).
var _workbench_mode: bool = false

# ---------------------------------------------------------------------------
# UI nodes
# ---------------------------------------------------------------------------

var _bg:           ColorRect = null
var _title_label:  Label     = null
var _slot_panels:  Array     = []  # Panel nodes (4 or 9)
var _slot_labels:  Array     = []  # Label nodes (4 or 9)
var _out_panel:    Panel     = null
var _out_label:    Label     = null
var _craft_btn:    Button    = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 12   # above ActionBarHUD (10) and EquipmentUI
	visible = false
	_build_ui()

func _build_ui() -> void:
	_rebuild_panel()

func _rebuild_panel() -> void:
	# Clear existing UI nodes
	for child in get_children():
		child.queue_free()
	_slot_panels = []
	_slot_labels = []
	_bg          = null
	_title_label = null
	_out_panel   = null
	_out_label   = null
	_craft_btn   = null

	var grid_cols: int = 3 if _workbench_mode else 2
	var grid_rows: int = 3 if _workbench_mode else 2

	var grid_w: int = grid_cols * SLOT_SIZE + (grid_cols - 1) * SLOT_GAP
	var grid_h: int = grid_rows * SLOT_SIZE + (grid_rows - 1) * SLOT_GAP

	var panel_w: int = PANEL_PAD * 2 + grid_w + 24 + SLOT_SIZE + 12 + 80
	var panel_h: int = PANEL_PAD + TITLE_H + grid_h + PANEL_PAD + 32 + PANEL_PAD

	var sw: int = 1280
	var sh: int = 720
	var px: int = (sw - panel_w) / 2
	var py: int = (sh - panel_h) / 2

	# Background panel
	_bg = ColorRect.new()
	_bg.position = Vector2(px, py)
	_bg.size     = Vector2(panel_w, panel_h)
	_bg.color    = COLOR_BG
	add_child(_bg)

	# Title
	_title_label = Label.new()
	_title_label.position = Vector2(px + PANEL_PAD, py + PANEL_PAD)
	_title_label.custom_minimum_size = Vector2(panel_w - PANEL_PAD * 2, TITLE_H)
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.add_theme_color_override("font_color", COLOR_TITLE)
	_title_label.text = "WORKBENCH  ( C to close )" if _workbench_mode \
	                  else "CRAFTING  ( C to close )"
	add_child(_title_label)

	# Grid slots
	for row in range(grid_rows):
		for col in range(grid_cols):
			var i := row * grid_cols + col
			var sx: int = px + GRID_X + col * (SLOT_SIZE + SLOT_GAP)
			var sy: int = py + GRID_Y + row * (SLOT_SIZE + SLOT_GAP)

			var panel := Panel.new()
			panel.position = Vector2(sx, sy)
			panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
			panel.modulate = COLOR_SLOT_EMPTY
			add_child(panel)
			_slot_panels.append(panel)

			var lbl := Label.new()
			lbl.position = Vector2(2, 2)
			lbl.custom_minimum_size = Vector2(SLOT_SIZE - 4, SLOT_SIZE - 4)
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.add_theme_color_override("font_color", COLOR_LABEL)
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			panel.add_child(lbl)
			_slot_labels.append(lbl)

			# Invisible button overlay for click handling
			var btn := Button.new()
			btn.position = Vector2(0, 0)
			btn.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
			btn.flat = true
			btn.focus_mode = Control.FOCUS_NONE
			var slot_i := i  # capture for lambda
			btn.pressed.connect(func() -> void: _on_slot_clicked(slot_i, false))
			btn.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed \
						and ev.button_index == MOUSE_BUTTON_RIGHT:
					_on_slot_clicked(slot_i, true))
			panel.add_child(btn)

	# Arrow label between grid and output
	var arrow_x: int = px + GRID_X + grid_w + 2
	var arrow_y: int = py + GRID_Y + (grid_h - 20) / 2
	var arrow := Label.new()
	arrow.position = Vector2(arrow_x, arrow_y)
	arrow.add_theme_font_size_override("font_size", 18)
	arrow.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	arrow.text = "→"
	add_child(arrow)

	# Output slot
	var out_x: int = arrow_x + 24
	var out_y: int = py + GRID_Y + (grid_h - SLOT_SIZE) / 2
	_out_panel = Panel.new()
	_out_panel.position = Vector2(out_x, out_y)
	_out_panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	_out_panel.modulate = COLOR_OUTPUT_OFF
	add_child(_out_panel)

	_out_label = Label.new()
	_out_label.position = Vector2(2, 2)
	_out_label.custom_minimum_size = Vector2(SLOT_SIZE - 4, SLOT_SIZE - 4)
	_out_label.add_theme_font_size_override("font_size", 9)
	_out_label.add_theme_color_override("font_color", COLOR_LABEL)
	_out_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_out_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_out_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_out_panel.add_child(_out_label)

	# Craft button
	_craft_btn = Button.new()
	_craft_btn.position = Vector2(out_x + SLOT_SIZE + 8, out_y + (SLOT_SIZE - 28) / 2)
	_craft_btn.custom_minimum_size = Vector2(72, 28)
	_craft_btn.text = "CRAFT"
	_craft_btn.add_theme_font_size_override("font_size", 11)
	_craft_btn.focus_mode = Control.FOCUS_NONE
	_craft_btn.pressed.connect(_do_craft)
	add_child(_craft_btn)

	# Close button
	var close_y: int = py + GRID_Y + grid_h + PANEL_PAD
	var close_btn := Button.new()
	close_btn.position = Vector2(px + (panel_w - 80) / 2, close_y)
	close_btn.custom_minimum_size = Vector2(80, 28)
	close_btn.text = "Close"
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(hide_ui)
	add_child(close_btn)

func show_ui() -> void:
	visible = true
	_refresh()

func hide_ui() -> void:
	visible = false

func toggle() -> void:
	if visible:
		hide_ui()
	else:
		_workbench_mode = false
		_grid = [{}, {}, {}, {}]
		_rebuild_panel()
		show_ui()

## Open in workbench mode (3×3 grid, all recipes available).
func open_workbench() -> void:
	_workbench_mode = true
	_grid = []
	for i in range(9):
		_grid.append({})
	_rebuild_panel()
	show_ui()

# ---------------------------------------------------------------------------
# Slot interaction
# ---------------------------------------------------------------------------

func _on_slot_clicked(slot_index: int, right_click: bool) -> void:
	if right_click:
		_grid[slot_index] = {}
	else:
		_cycle_slot(slot_index)
	_update_match()
	_refresh()

func _cycle_slot(slot_index: int) -> void:
	# Cycleable items include materials AND structures (so campfire/workbench can be placed)
	var options := _bag_cycleable_ids()
	if options.is_empty():
		_grid[slot_index] = {}
		return
	var current_id: String = str((_grid[slot_index] as Dictionary).get("id", ""))
	var idx := options.find(current_id)
	if idx == -1:
		# Slot empty or item no longer in bag — fill with first option.
		var first_id: String = options[0]
		_grid[slot_index] = {"id": first_id, "category": _item_category(first_id), "count": 1}
	elif idx >= options.size() - 1:
		# Already at last option — clear the slot.
		_grid[slot_index] = {}
	else:
		var next_id: String = options[idx + 1]
		_grid[slot_index] = {"id": next_id, "category": _item_category(next_id), "count": 1}

## Returns a deduplicated list of material item IDs currently in the bag (count > 0).
## Used for recipe ingredient selection (excludes non-material categories).
func _bag_material_ids() -> Array:
	if inventory == null:
		return []
	var seen: Dictionary = {}
	for i in range(inventory.BAG_SIZE):
		var slot: Dictionary = inventory.bag[i] as Dictionary
		if slot.is_empty():
			continue
		if str(slot.get("category", "")) != "material":
			continue
		var id: String = str(slot.get("id", ""))
		if id != "" and not seen.has(id):
			seen[id] = true
	return seen.keys()

## Returns material IDs for recipe purposes (materials only — no structures in recipe grid).
## Structures are cycleable in the grid but match no recipe input, so they just
## won't produce a match. Keeping them out of recipe slot cycling avoids confusion.
func _bag_cycleable_ids() -> Array:
	return _bag_material_ids()

## Look up the category of an item id from inventory bag.
func _item_category(item_id: String) -> String:
	if inventory == null:
		return "material"
	for i in range(inventory.BAG_SIZE):
		var slot: Dictionary = inventory.bag[i] as Dictionary
		if not slot.is_empty() and str(slot.get("id", "")) == item_id:
			return str(slot.get("category", "material"))
	return "material"

# ---------------------------------------------------------------------------
# Recipe matching
# ---------------------------------------------------------------------------

func _update_match() -> void:
	var grid_items: Dictionary = {}
	for slot in _grid:
		var s := slot as Dictionary
		if s.is_empty():
			continue
		var id: String = str(s.get("id", ""))
		if id != "":
			grid_items[id] = int(grid_items.get(id, 0)) + 1

	_matched = RecipeRegistry.match_recipe(grid_items, _workbench_mode)
	_can_craft = _check_can_craft()

func _check_can_craft() -> bool:
	if _matched.is_empty() or inventory == null:
		return false
	# Build required ingredient counts from grid
	var required: Dictionary = {}
	for slot in _grid:
		var s := slot as Dictionary
		if s.is_empty():
			continue
		var id: String = str(s.get("id", ""))
		if id != "":
			required[id] = int(required.get(id, 0)) + 1
	for id in required:
		if inventory.bag_stack_total(id) < int(required[id]):
			return false
	return true

# ---------------------------------------------------------------------------
# Crafting
# ---------------------------------------------------------------------------

func _do_craft() -> void:
	if not _can_craft:
		return
	# Consume ingredients from bag
	var required: Dictionary = {}
	for slot in _grid:
		var s := slot as Dictionary
		if s.is_empty():
			continue
		var id: String = str(s.get("id", ""))
		if id != "":
			required[id] = int(required.get(id, 0)) + 1
	for id in required:
		inventory.remove_from_bag(id, int(required[id]))
	# Route output to the right place:
	#   tools / structures → first free tool slot, else bag
	#   anything else → bag
	var output_id: String       = str(_matched.get("id", ""))
	var output_category: String = str(_matched.get("category", ""))
	var equipped := false
	if output_category == "tool" or output_category == "structure":
		for i in range(inventory.TOOL_SLOT_COUNT):
			if (inventory.tool_slots[i] as Dictionary).is_empty():
				inventory.set_tool_slot(i, _matched)
				print("[CRAFT] made and equipped %s → tool slot %d" % [output_id, i])
				equipped = true
				break
	if not equipped:
		inventory.add_to_bag(_matched, 99)
		print("[CRAFT] made %s → bag" % output_id)
	# Clear grid
	var grid_size: int = _grid.size()
	_grid = []
	for i in range(grid_size):
		_grid.append({})
	_matched = {}
	_can_craft = false
	_refresh()

# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

func _refresh() -> void:
	_update_match()
	# Grid slots
	for i in range(_grid.size()):
		if i >= _slot_panels.size():
			break
		var s := _grid[i] as Dictionary
		var panel: Panel  = _slot_panels[i]
		var lbl:   Label  = _slot_labels[i]
		if s.is_empty():
			panel.modulate = COLOR_SLOT_EMPTY
			lbl.text = ""
		else:
			panel.modulate = COLOR_SLOT_FULL
			lbl.text = str(s.get("id", "")).replace("_", "\n")
	# Output slot
	if _matched.is_empty():
		_out_panel.modulate = COLOR_OUTPUT_OFF
		_out_label.text = ""
		_craft_btn.modulate = COLOR_CRAFT_OFF
		_craft_btn.disabled = true
	else:
		_out_panel.modulate = COLOR_OUTPUT_ON if _can_craft else COLOR_OUTPUT_OFF
		_out_label.text = str(_matched.get("id", "")).replace("_", "\n")
		_craft_btn.modulate = COLOR_CRAFT_ON if _can_craft else COLOR_CRAFT_OFF
		_craft_btn.disabled = not _can_craft

func _process(_delta: float) -> void:
	# Re-check can_craft each frame so the button state tracks bag changes in
	# real time (e.g. picking up more wood while the UI is open).
	if visible:
		var was := _can_craft
		_can_craft = _check_can_craft()
		if was != _can_craft:
			_refresh()
