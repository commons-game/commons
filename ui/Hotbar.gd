## Hotbar — horizontal bar at bottom-center showing active items.
##
## Layout (left → right):
##   [ tool_slot 0 ] [ tool_slot 1 ] | [ bag 0 ] [ bag 1 ] [ bag 2 ] [ bag 3 ] [ bag 4 ] [ bag 5 ]
##
## Active slot has a bright highlight border.
## Item count shown in bottom-right corner of each slot.
## Item id shown as short label (no icon yet).
## Scroll wheel and 1–8 keys cycle active slot.
##
## Wiring:
##   hotbar.inventory = $Player.inventory
##   hotbar.player = $Player
## then add_child.
extends CanvasLayer

var inventory: Object = null  # Inventory
var player: Node = null

const SLOT_SIZE      := 40
const SLOT_GAP       := 4
const TOOL_BAG_GAP   := 12   # wider gap between tool section and bag section
const TOOL_SLOTS     := 2
const BAG_SHOWN      := 6

## Combined slot count for the hotbar: tool0, tool1, bag0..bag5.
const TOTAL_SLOTS    := TOOL_SLOTS + BAG_SHOWN

## Active slot index (0..TOTAL_SLOTS-1).
var active_index: int = 0

const COLOR_BG_EMPTY  := Color(0.12, 0.12, 0.12, 0.80)
const COLOR_BG_FILLED := Color(0.22, 0.22, 0.22, 0.90)
const COLOR_ACTIVE    := Color(0.35, 0.35, 0.15, 0.95)
const COLOR_BORDER    := Color(0.30, 0.55, 0.85)
const COLOR_ACTIVE_BORDER := Color(1.0, 0.90, 0.2)
const COLOR_TOOL_SECTION  := Color(0.30, 0.55, 0.85)
const COLOR_BAG_SECTION   := Color(0.40, 0.40, 0.40)
const COLOR_LABEL         := Color(1.0, 1.0, 0.9)
const COLOR_COUNT         := Color(0.9, 0.85, 0.4)

var _panels: Array = []   # ColorRect per slot
var _id_labels: Array = []   # Label: item id
var _count_labels: Array = []  # Label: count

const BAR_HEIGHT     := 5
const BAR_GAP        := 3
var _hp_bar_bg: ColorRect   = null
var _hp_bar_fill: ColorRect = null
var _food_bar_bg: ColorRect   = null
var _food_bar_fill: ColorRect = null
var _bar_total_width: int = 0

func _ready() -> void:
	layer = 11   # above ActionBarHUD (10)
	_build_ui()

func _build_ui() -> void:
	var total_width: int = (TOTAL_SLOTS * SLOT_SIZE
	                        + (TOTAL_SLOTS - 1) * SLOT_GAP
	                        + TOOL_BAG_GAP)  # extra gap between sections
	var start_x: int = (1280 - total_width) / 2
	var y: int = 720 - SLOT_SIZE - 50  # above ActionBarHUD

	for i in range(TOTAL_SLOTS):
		var extra_x: int = TOOL_BAG_GAP if i >= TOOL_SLOTS else 0
		var x: int = start_x + i * (SLOT_SIZE + SLOT_GAP) + extra_x

		var panel := ColorRect.new()
		panel.position = Vector2(x, y)
		panel.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		panel.color = COLOR_BG_EMPTY
		add_child(panel)
		_panels.append(panel)

		# Border indicator — bottom strip
		var border := ColorRect.new()
		border.position = Vector2(0, SLOT_SIZE - 3)
		border.size = Vector2(SLOT_SIZE, 3)
		border.color = COLOR_TOOL_SECTION if i < TOOL_SLOTS else COLOR_BAG_SECTION
		panel.add_child(border)

		# Item id label (top of slot)
		var id_lbl := Label.new()
		id_lbl.position = Vector2(2, 2)
		id_lbl.size = Vector2(SLOT_SIZE - 4, SLOT_SIZE - 14)
		id_lbl.add_theme_font_size_override("font_size", 8)
		id_lbl.add_theme_color_override("font_color", COLOR_LABEL)
		id_lbl.text = ""
		id_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		id_lbl.clip_contents = true
		panel.add_child(id_lbl)
		_id_labels.append(id_lbl)

		# Count label (bottom-right of slot)
		var cnt_lbl := Label.new()
		cnt_lbl.position = Vector2(SLOT_SIZE - 18, SLOT_SIZE - 14)
		cnt_lbl.size = Vector2(16, 12)
		cnt_lbl.add_theme_font_size_override("font_size", 8)
		cnt_lbl.add_theme_color_override("font_color", COLOR_COUNT)
		cnt_lbl.text = ""
		cnt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(cnt_lbl)
		_count_labels.append(cnt_lbl)

	# HP bar — background + fill above slots
	_bar_total_width = total_width
	var hp_bar_y: int = y - BAR_GAP - BAR_HEIGHT - BAR_GAP - BAR_HEIGHT
	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.position = Vector2(start_x, hp_bar_y)
	_hp_bar_bg.size = Vector2(total_width, BAR_HEIGHT)
	_hp_bar_bg.color = Color(0.25, 0.05, 0.05, 0.85)
	add_child(_hp_bar_bg)
	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.position = Vector2(start_x, hp_bar_y)
	_hp_bar_fill.size = Vector2(total_width, BAR_HEIGHT)
	_hp_bar_fill.color = Color(0.85, 0.15, 0.15)
	add_child(_hp_bar_fill)

	# Food bar — below HP bar, above slots
	var food_bar_y: int = y - BAR_GAP - BAR_HEIGHT
	_food_bar_bg = ColorRect.new()
	_food_bar_bg.position = Vector2(start_x, food_bar_y)
	_food_bar_bg.size = Vector2(total_width, BAR_HEIGHT)
	_food_bar_bg.color = Color(0.15, 0.15, 0.05, 0.85)
	add_child(_food_bar_bg)
	_food_bar_fill = ColorRect.new()
	_food_bar_fill.position = Vector2(start_x, food_bar_y)
	_food_bar_fill.size = Vector2(total_width, BAR_HEIGHT)
	_food_bar_fill.color = Color(0.75, 0.65, 0.15)
	add_child(_food_bar_fill)

	# Key hint labels
	for i in range(TOTAL_SLOTS):
		var extra_x: int = TOOL_BAG_GAP if i >= TOOL_SLOTS else 0
		var x: int = start_x + i * (SLOT_SIZE + SLOT_GAP) + extra_x
		var hint := Label.new()
		hint.position = Vector2(x, y + SLOT_SIZE + 2)
		hint.size = Vector2(SLOT_SIZE, 12)
		hint.add_theme_font_size_override("font_size", 8)
		hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		hint.text = "[%d]" % (i + 1)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(hint)

## Call to sync displayed items with inventory.
func refresh() -> void:
	if inventory == null:
		return
	for i in range(TOTAL_SLOTS):
		var stack: Dictionary = _get_slot_stack(i)
		_update_slot(i, stack)

## Return the ItemStack dict for hotbar index i, or {}.
func _get_slot_stack(i: int) -> Dictionary:
	if inventory == null:
		return {}
	if i < TOOL_SLOTS:
		return inventory.tool_slots[i] as Dictionary
	var bag_i: int = i - TOOL_SLOTS
	if bag_i < inventory.BAG_SIZE:
		return inventory.bag[bag_i] as Dictionary
	return {}

## Return the currently active slot's ItemStack, or {}.
func get_active_stack() -> Dictionary:
	return _get_slot_stack(active_index)

func _update_slot(i: int, stack: Dictionary) -> void:
	if i >= _panels.size():
		return
	var panel: ColorRect = _panels[i]
	var id_lbl: Label = _id_labels[i]
	var cnt_lbl: Label = _count_labels[i]

	if stack.is_empty():
		panel.color = COLOR_ACTIVE if i == active_index else COLOR_BG_EMPTY
		id_lbl.text = ""
		cnt_lbl.text = ""
	else:
		panel.color = COLOR_ACTIVE if i == active_index else COLOR_BG_FILLED
		var raw: String = str(stack.get("id", ""))
		id_lbl.text = raw.replace("_", "\n").left(10)
		var cnt: int = int(stack.get("count", 1))
		cnt_lbl.text = str(cnt) if cnt > 1 else ""

	# Update border color to indicate active
	var border: ColorRect = panel.get_child(0) as ColorRect
	if border != null:
		if i == active_index:
			border.color = COLOR_ACTIVE_BORDER
		elif i < TOOL_SLOTS:
			border.color = COLOR_TOOL_SECTION
		else:
			border.color = COLOR_BAG_SECTION

func _set_active(i: int) -> void:
	i = clampi(i, 0, TOTAL_SLOTS - 1)
	active_index = i
	refresh()

func _unhandled_input(event: InputEvent) -> void:
	# Number keys 1-8
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _set_active(0)
			KEY_2: _set_active(1)
			KEY_3: _set_active(2)
			KEY_4: _set_active(3)
			KEY_5: _set_active(4)
			KEY_6: _set_active(5)
			KEY_7: _set_active(6)
			KEY_8: _set_active(7)
	# Scroll wheel
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_active((active_index - 1 + TOTAL_SLOTS) % TOTAL_SLOTS)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_active((active_index + 1) % TOTAL_SLOTS)

var _frame_counter: int = 0

func _process(_delta: float) -> void:
	_frame_counter += 1
	if _frame_counter >= 6:
		_frame_counter = 0
		refresh()
		_refresh_bars()

func _refresh_bars() -> void:
	if player == null or _hp_bar_fill == null:
		return
	# HP
	var health_node = player.get_node_or_null("Health")
	if health_node != null:
		var frac: float = float(health_node.get("current_hp")) / float(health_node.get("max_hp"))
		frac = clampf(frac, 0.0, 1.0)
		_hp_bar_fill.size.x = _bar_total_width * frac
	# Food
	var max_food: int = int(player.get("max_food")) if player.get("max_food") else 100
	var food: int = int(player.get("food")) if player.get("food") != null else 0
	var food_frac: float = clampf(float(food) / float(max_food), 0.0, 1.0)
	_food_bar_fill.size.x = _bar_total_width * food_frac
