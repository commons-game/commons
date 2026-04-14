## ActionBarHUD — always-visible action bar at the bottom of the screen.
##
## Layout (left → right):
##   [ weapon* ]  [ tool 0 ]  [ tool 1 ]  [ talisman* ]
##
## Fixed slots show a colored border. Talisman slot pulses when awakened.
## Driven by a reference to the player's Inventory — call refresh() after
## any inventory change to update display.
##
## Wiring (set before add_child or in World._setup_day_night_system equivalent):
##   inventory: Inventory object from Player
extends CanvasLayer

var inventory: Object = null  # Inventory

const SLOT_SIZE   := 40
const SLOT_GAP    := 6
const SLOT_COUNT  := 4  # weapon + tool0 + tool1 + talisman
const BAR_HEIGHT  := SLOT_SIZE + 16

## Slot index constants
const SLOT_WEAPON   := 0
const SLOT_TOOL_0   := 1
const SLOT_TOOL_1   := 2
const SLOT_TALISMAN := 3

## Colors
const COLOR_EMPTY           := Color(0.15, 0.15, 0.15, 0.8)
const COLOR_FILLED          := Color(0.25, 0.25, 0.25, 0.9)
const COLOR_ACTIVE          := Color(0.35, 0.35, 0.15, 0.95)  # yellow tint for active tool
const COLOR_WEAPON_BORDER   := Color(0.9, 0.3, 0.3)
const COLOR_TALISMAN_BORDER := Color(0.6, 0.3, 0.9)
const COLOR_TOOL_BORDER     := Color(0.3, 0.6, 0.9)
const COLOR_ACTIVE_BORDER   := Color(1.0, 0.9, 0.2)           # bright yellow for active slot
const COLOR_AWAKENED        := Color(0.9, 0.5, 1.0)
const COLOR_LABEL           := Color(1.0, 1.0, 0.9)

var _panels: Array = []    # Panel nodes, one per slot
var _labels: Array = []    # Label nodes, one per slot
var _borders: Array = []   # ColorRect border indicator per slot
var _bag_label: Label = null  # shows bag item counts below action bar

func _ready() -> void:
	layer = 10
	_build_ui()

func _build_ui() -> void:
	var total_width: int = SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_GAP
	var start_x: int = (1280 - total_width) / 2
	var y: int = 720 - BAR_HEIGHT

	for i in range(SLOT_COUNT):
		var x: int = start_x + i * (SLOT_SIZE + SLOT_GAP)

		var panel := Panel.new()
		panel.position = Vector2(x, y)
		panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		panel.modulate = COLOR_EMPTY
		add_child(panel)
		_panels.append(panel)

		# Slot border color indicator
		var border := ColorRect.new()
		border.position = Vector2(0, SLOT_SIZE - 3)
		border.size = Vector2(SLOT_SIZE, 3)
		border.color = _border_color(i)
		panel.add_child(border)
		_borders.append(border)

		# Item label (abbreviated id)
		var lbl := Label.new()
		lbl.position = Vector2(2, 2)
		lbl.custom_minimum_size = Vector2(SLOT_SIZE - 4, SLOT_SIZE - 4)
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", COLOR_LABEL)
		lbl.text = ""
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(lbl)
		_labels.append(lbl)

	# Slot key hint labels below bar
	var slot_names := ["WPN", "[1]", "[2]", "TAL"]
	for i in range(SLOT_COUNT):
		var x: int = start_x + i * (SLOT_SIZE + SLOT_GAP)
		var name_lbl := Label.new()
		name_lbl.position = Vector2(x, y + SLOT_SIZE + 2)
		name_lbl.custom_minimum_size = Vector2(SLOT_SIZE, 12)
		name_lbl.add_theme_font_size_override("font_size", 9)
		name_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		name_lbl.text = slot_names[i]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(name_lbl)

	# Bag item summary label (shows dirt count etc. while digging)
	_bag_label = Label.new()
	_bag_label.position = Vector2(start_x, y - 18)
	_bag_label.custom_minimum_size = Vector2(total_width, 14)
	_bag_label.add_theme_font_size_override("font_size", 10)
	_bag_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	_bag_label.text = ""
	add_child(_bag_label)

func _border_color(slot_index: int) -> Color:
	match slot_index:
		SLOT_WEAPON:   return COLOR_WEAPON_BORDER
		SLOT_TALISMAN: return COLOR_TALISMAN_BORDER
		_:             return COLOR_TOOL_BORDER

## Call after any inventory change to redraw the bar.
func refresh() -> void:
	if inventory == null:
		return
	_update_slot(SLOT_WEAPON,   inventory.weapon_slot)
	_update_slot(SLOT_TOOL_0,   inventory.tool_slots[0])
	_update_slot(SLOT_TOOL_1,   inventory.tool_slots[1])
	_update_slot(SLOT_TALISMAN, inventory.talisman_slot)

	# Active tool highlight — tool slots only (indices 1 and 2 in the bar)
	var active_bar_slot: int = SLOT_TOOL_0 + inventory.active_tool_index
	for i in [SLOT_TOOL_0, SLOT_TOOL_1]:
		if _borders.size() > i:
			(_borders[i] as ColorRect).color = \
				COLOR_ACTIVE_BORDER if i == active_bar_slot else COLOR_TOOL_BORDER
		if _panels.size() > i:
			var slot_stack: Dictionary = inventory.tool_slots[i - SLOT_TOOL_0] as Dictionary
			(_panels[i] as Panel).modulate = \
				COLOR_ACTIVE if i == active_bar_slot and not slot_stack.is_empty() \
				else (COLOR_FILLED if not slot_stack.is_empty() else COLOR_EMPTY)

	# Talisman awakened visual
	if _panels.size() > SLOT_TALISMAN:
		var awakened: bool = inventory.talisman_awakened
		var tal_panel: Panel = _panels[SLOT_TALISMAN]
		tal_panel.modulate = COLOR_AWAKENED if awakened else (
			COLOR_FILLED if not inventory.talisman_slot.is_empty() else COLOR_EMPTY)

	# Bag summary — show non-zero material counts
	_refresh_bag_label()

func _refresh_bag_label() -> void:
	if _bag_label == null or inventory == null:
		return
	# Collect material items with count > 0
	var seen: Dictionary = {}
	for i in range(inventory.BAG_SIZE):
		var slot: Dictionary = inventory.bag[i] as Dictionary
		if slot.is_empty():
			continue
		var id: String = str(slot.get("id", ""))
		var cnt: int = int(slot.get("count", 0))
		seen[id] = int(seen.get(id, 0)) + cnt
	if seen.is_empty():
		_bag_label.text = ""
		return
	var parts: Array = []
	for id in seen:
		parts.append("%s×%d" % [id, seen[id]])
	_bag_label.text = "Bag: " + ", ".join(parts)

func _update_slot(index: int, stack: Dictionary) -> void:
	if index >= _panels.size():
		return
	var panel: Panel = _panels[index]
	var lbl: Label = _labels[index]
	if stack.is_empty():
		panel.modulate = COLOR_EMPTY
		lbl.text = ""
	else:
		panel.modulate = COLOR_FILLED
		# Abbreviate: first 6 chars of display id, replace _ with newline for readability
		var raw: String = str(stack.get("id", ""))
		lbl.text = raw.replace("_", "\n").left(12)

var _frame_counter: int = 0

func _process(_delta: float) -> void:
	# Poll inventory every 6 frames so changes (dig/place) reflect immediately
	# without needing explicit refresh() calls from every caller.
	_frame_counter += 1
	if _frame_counter >= 6:
		_frame_counter = 0
		refresh()

	# Pulse the talisman slot when awakened
	if inventory == null or _panels.size() <= SLOT_TALISMAN:
		return
	if inventory.talisman_awakened:
		var pulse := (sin(Time.get_ticks_msec() * 0.004) * 0.15) + 0.85
		var col := COLOR_AWAKENED
		col.a = pulse
		(_panels[SLOT_TALISMAN] as Panel).modulate = col
