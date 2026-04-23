## Hotbar + Inventory UI
##
## Always-visible bottom bar: bag slots 0–7 (8 slots).
## Tab/I toggles expanded inventory panel above the hotbar showing:
##   Row 2 : bag slots 8–11
##   Side  : tool_slot 0, tool_slot 1, weapon_slot, talisman_slot
##
## Active slot (bright highlight) cycles through hotbar slots only.
## Scroll wheel and 1–8 keys change the active slot.
##
## Drag & drop:
##   Left-click  : pick up stack / swap / place
##   Right-click : split (take half from filled slot, place one on filled slot)
##   Escape / Tab while holding : cancel drag, return stack to origin
##
## Interface for Player.gd:
##   get_active_stack() → ItemStack dict from bag[active_index]
##
## Wiring (World.gd):
##   hotbar.inventory = $Player.inventory
##   hotbar.player    = $Player
##   add_child(hotbar)
##   hotbar.refresh()
extends CanvasLayer

const ITEM_ICON_ATLAS := preload("res://tilesets/placeholder_tileset.png")
const ICON_TILE_PX    := 16   # atlas tile size in pixels

var inventory: Object = null  # Inventory
var player: Node = null

# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------
const SLOT_SIZE   := 40
const SLOT_GAP    := 4
const SECTION_GAP := 12   # gap between bag row and side-panel columns

const HOTBAR_SLOTS := 8        # bag[0..7]
const HOTBAR_BAG_EXTRA := 4    # bag[8..11]  — second row in expanded view
const TOOL_SLOT_COUNT := 2     # tool_slots[0..1]

const BAR_HEIGHT := 5
const BAR_GAP    := 3

# Colours
const COLOR_BG_EMPTY      := Color(0.12, 0.12, 0.12, 0.80)
const COLOR_BG_FILLED     := Color(0.22, 0.22, 0.22, 0.90)
const COLOR_ACTIVE        := Color(0.35, 0.35, 0.15, 0.95)
const COLOR_BORDER_NORMAL := Color(0.40, 0.40, 0.40)
const COLOR_BORDER_TOOL   := Color(0.30, 0.55, 0.85)
const COLOR_BORDER_WEAPON := Color(0.75, 0.25, 0.25)
const COLOR_BORDER_TALISM := Color(0.55, 0.20, 0.75)
const COLOR_ACTIVE_BORDER := Color(1.0,  0.90, 0.2)
const COLOR_LABEL         := Color(1.0,  1.0,  0.9)
const COLOR_COUNT         := Color(0.9,  0.85, 0.4)
const COLOR_DRAG_CURSOR   := Color(0.85, 0.75, 0.20, 0.92)
const COLOR_EXPANDED_BG   := Color(0.08, 0.08, 0.08, 0.88)

# ---------------------------------------------------------------------------
# Slot descriptor — one entry per rendered slot
# ---------------------------------------------------------------------------
# type: "hotbar" | "extra_bag" | "tool" | "weapon" | "talisman"
# index: relevant array index (bag index, tool index, etc.)
var _slots: Array = []  # Array of Dictionaries

# Per-slot nodes
var _panels:        Array = []
var _icon_bgs:      Array = []   # ColorRect — solid icon colour (category/item)
var _icon_textures: Array = []   # TextureRect — atlas crop (when item has icon_atlas)
var _name_labels:   Array = []   # Label — abbreviated item name below icon
var _count_labels:  Array = []
var _borders:       Array = []

# HP / food bars
var _hp_bar_bg:     ColorRect = null
var _hp_bar_fill:   ColorRect = null
var _food_bar_bg:   ColorRect = null
var _food_bar_fill: ColorRect = null
var _bar_total_width: int = 0

# Expanded panel background
var _expanded_bg: ColorRect = null
var _expanded_visible: bool = false

# Active hotbar slot (0..HOTBAR_SLOTS-1)
var active_index: int = 0

# Drag state
var _drag_stack:      Dictionary = {}   # stack being dragged (copy)
var _drag_origin:     int = -1          # slot index of origin, -1 = none
var _drag_cursor:     Control = null    # visual following mouse
var _drag_cursor_lbl: Label = null

# Geometry cache (set in _build_ui)
var _hotbar_start_x: int = 0
var _hotbar_y:       int = 0

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	layer = 11
	_build_ui()

# ---------------------------------------------------------------------------
# Build UI
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	# Hotbar row
	var hotbar_width: int = HOTBAR_SLOTS * SLOT_SIZE + (HOTBAR_SLOTS - 1) * SLOT_GAP
	_hotbar_start_x = (1280 - hotbar_width) / 2
	_hotbar_y = 720 - SLOT_SIZE - 50

	# HP bar
	var hp_y := _hotbar_y - BAR_GAP - BAR_HEIGHT - BAR_GAP - BAR_HEIGHT
	_bar_total_width = hotbar_width
	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.position = Vector2(_hotbar_start_x, hp_y)
	_hp_bar_bg.size = Vector2(hotbar_width, BAR_HEIGHT)
	_hp_bar_bg.color = Color(0.25, 0.05, 0.05, 0.85)
	add_child(_hp_bar_bg)
	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.position = Vector2(_hotbar_start_x, hp_y)
	_hp_bar_fill.size = Vector2(hotbar_width, BAR_HEIGHT)
	_hp_bar_fill.color = Color(0.85, 0.15, 0.15)
	add_child(_hp_bar_fill)

	# Food bar
	var food_y := _hotbar_y - BAR_GAP - BAR_HEIGHT
	_food_bar_bg = ColorRect.new()
	_food_bar_bg.position = Vector2(_hotbar_start_x, food_y)
	_food_bar_bg.size = Vector2(hotbar_width, BAR_HEIGHT)
	_food_bar_bg.color = Color(0.15, 0.15, 0.05, 0.85)
	add_child(_food_bar_bg)
	_food_bar_fill = ColorRect.new()
	_food_bar_fill.position = Vector2(_hotbar_start_x, food_y)
	_food_bar_fill.size = Vector2(hotbar_width, BAR_HEIGHT)
	_food_bar_fill.color = Color(0.75, 0.65, 0.15)
	add_child(_food_bar_fill)

	# Expanded panel background (hidden initially)
	# Height: one extra bag row + one tool/equip row, with gaps
	var exp_rows_height := (SLOT_SIZE + SLOT_GAP) * 2 + SLOT_GAP
	_expanded_bg = ColorRect.new()
	_expanded_bg.position = Vector2(_hotbar_start_x - 4, _hotbar_y - exp_rows_height - 8)
	_expanded_bg.size = Vector2(hotbar_width + 8, exp_rows_height + 8)
	_expanded_bg.color = COLOR_EXPANDED_BG
	_expanded_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_expanded_bg.visible = false
	add_child(_expanded_bg)

	# Build slot descriptors and panels
	_build_hotbar_slots()
	_build_expanded_slots()

	# Key hint labels below hotbar
	for i in range(HOTBAR_SLOTS):
		var hx: int = _hotbar_start_x + i * (SLOT_SIZE + SLOT_GAP)
		var hint := Label.new()
		hint.position = Vector2(hx, _hotbar_y + SLOT_SIZE + 2)
		hint.size = Vector2(SLOT_SIZE, 12)
		hint.add_theme_font_size_override("font_size", 8)
		hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		hint.text = "[%d]" % (i + 1)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(hint)

	# Drag cursor (always on top, hidden until drag starts)
	_drag_cursor = ColorRect.new()
	_drag_cursor.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	_drag_cursor.color = Color(0.12, 0.12, 0.12, 0.80)
	_drag_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_cursor.z_index = 100
	_drag_cursor.visible = false
	add_child(_drag_cursor)
	# Icon area inside drag cursor
	var drag_icon_bg := ColorRect.new()
	drag_icon_bg.name = "IconBg"
	drag_icon_bg.position = Vector2(4, 4)
	drag_icon_bg.size = Vector2(SLOT_SIZE - 8, SLOT_SIZE - 12)
	drag_icon_bg.color = COLOR_DRAG_CURSOR
	_drag_cursor.add_child(drag_icon_bg)
	var drag_icon_tex := TextureRect.new()
	drag_icon_tex.name = "IconTex"
	drag_icon_tex.position = Vector2(4, 4)
	drag_icon_tex.size = Vector2(SLOT_SIZE - 8, SLOT_SIZE - 12)
	drag_icon_tex.stretch_mode = TextureRect.STRETCH_SCALE
	drag_icon_tex.texture = null
	_drag_cursor.add_child(drag_icon_tex)
	_drag_cursor_lbl = Label.new()
	_drag_cursor_lbl.position = Vector2(SLOT_SIZE - 18, SLOT_SIZE - 14)
	_drag_cursor_lbl.size = Vector2(16, 12)
	_drag_cursor_lbl.add_theme_font_size_override("font_size", 8)
	_drag_cursor_lbl.add_theme_color_override("font_color", COLOR_COUNT)
	_drag_cursor_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_drag_cursor.add_child(_drag_cursor_lbl)

func _build_hotbar_slots() -> void:
	for i in range(HOTBAR_SLOTS):
		var x: int = _hotbar_start_x + i * (SLOT_SIZE + SLOT_GAP)
		_add_slot({"type": "hotbar", "index": i},
		          x, _hotbar_y, COLOR_BORDER_NORMAL)

func _build_expanded_slots() -> void:
	# Row above hotbar: bag[8..11] in first 4 columns, then gap, then tool/equip slots
	var row_y := _hotbar_y - SLOT_SIZE - SLOT_GAP

	# Extra bag row: 4 slots
	for i in range(HOTBAR_BAG_EXTRA):
		var x: int = _hotbar_start_x + i * (SLOT_SIZE + SLOT_GAP)
		_add_slot({"type": "extra_bag", "index": HOTBAR_SLOTS + i},
		          x, row_y, COLOR_BORDER_NORMAL)

	# Tool slots (after bag row, with a section gap)
	var side_x_start: int = _hotbar_start_x + HOTBAR_BAG_EXTRA * (SLOT_SIZE + SLOT_GAP) + SECTION_GAP
	for i in range(TOOL_SLOT_COUNT):
		var x: int = side_x_start + i * (SLOT_SIZE + SLOT_GAP)
		_add_slot({"type": "tool", "index": i},
		          x, row_y, COLOR_BORDER_TOOL)

	# Weapon slot
	var weapon_x: int = side_x_start + TOOL_SLOT_COUNT * (SLOT_SIZE + SLOT_GAP)
	_add_slot({"type": "weapon", "index": 0}, weapon_x, row_y, COLOR_BORDER_WEAPON)

	# Talisman slot
	var talism_x: int = weapon_x + SLOT_SIZE + SLOT_GAP
	_add_slot({"type": "talisman", "index": 0}, talism_x, row_y, COLOR_BORDER_TALISM)

func _add_slot(desc: Dictionary, x: int, y: int, border_color: Color) -> void:
	var panel := ColorRect.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	panel.color = COLOR_BG_EMPTY
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_panels.append(panel)
	_slots.append(desc)

	var border := ColorRect.new()
	border.position = Vector2(0, SLOT_SIZE - 3)
	border.size = Vector2(SLOT_SIZE, 3)
	border.color = border_color
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(border)
	_borders.append(border)

	# Icon background — filled with item's icon_color when occupied.
	# Shorter than before to leave room for the name label at the bottom.
	var icon_bg := ColorRect.new()
	icon_bg.position = Vector2(4, 2)
	icon_bg.size = Vector2(SLOT_SIZE - 8, 20)
	icon_bg.color = Color.TRANSPARENT
	icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon_bg)
	_icon_bgs.append(icon_bg)

	var icon_tex := TextureRect.new()
	icon_tex.position = Vector2(4, 2)
	icon_tex.size = Vector2(SLOT_SIZE - 8, 20)
	icon_tex.stretch_mode = TextureRect.STRETCH_SCALE
	icon_tex.texture = null
	icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon_tex)
	_icon_textures.append(icon_tex)

	# Item name — small, below the icon
	var name_lbl := Label.new()
	name_lbl.position = Vector2(1, 23)
	name_lbl.size = Vector2(SLOT_SIZE - 2, 11)
	name_lbl.add_theme_font_size_override("font_size", 7)
	name_lbl.add_theme_color_override("font_color", COLOR_LABEL)
	name_lbl.text = ""
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.clip_contents = true
	panel.add_child(name_lbl)
	_name_labels.append(name_lbl)

	# Stack count — bottom-right corner, overlaps name for multi-stack items
	var cnt_lbl := Label.new()
	cnt_lbl.position = Vector2(SLOT_SIZE - 16, 24)
	cnt_lbl.size = Vector2(14, 10)
	cnt_lbl.add_theme_font_size_override("font_size", 7)
	cnt_lbl.add_theme_color_override("font_color", COLOR_COUNT)
	cnt_lbl.text = ""
	cnt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(cnt_lbl)
	_count_labels.append(cnt_lbl)

	# Hide expanded slots by default
	var is_expanded: bool = (str(desc.get("type", "")) != "hotbar")
	panel.visible = not is_expanded

# ---------------------------------------------------------------------------
# Inventory accessors
# ---------------------------------------------------------------------------

func _get_slot_stack(slot_i: int) -> Dictionary:
	if inventory == null or slot_i < 0 or slot_i >= _slots.size():
		return {}
	var desc: Dictionary = _slots[slot_i]
	var t: String = str(desc.get("type", ""))
	var idx: int = int(desc.get("index", 0))
	match t:
		"hotbar", "extra_bag":
			return inventory.bag[idx] as Dictionary
		"tool":
			return inventory.tool_slots[idx] as Dictionary
		"weapon":
			return inventory.weapon_slot as Dictionary
		"talisman":
			return inventory.talisman_slot as Dictionary
	return {}

func _set_slot_stack(slot_i: int, stack: Dictionary) -> void:
	if inventory == null or slot_i < 0 or slot_i >= _slots.size():
		return
	var desc: Dictionary = _slots[slot_i]
	var t: String = str(desc.get("type", ""))
	var idx: int = int(desc.get("index", 0))
	match t:
		"hotbar", "extra_bag":
			inventory.bag[idx] = stack
		"tool":
			inventory.tool_slots[idx] = stack
		"weapon":
			inventory.weapon_slot = stack
		"talisman":
			inventory.talisman_slot = stack

## Return the active hotbar slot's ItemStack (bag[active_index]).
func get_active_stack() -> Dictionary:
	if inventory == null:
		return {}
	return inventory.bag[active_index] as Dictionary

# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func refresh() -> void:
	if inventory == null:
		return
	for i in range(_slots.size()):
		_update_slot(i, _get_slot_stack(i))

func _update_slot(i: int, stack: Dictionary) -> void:
	if i >= _panels.size():
		return
	var panel: ColorRect      = _panels[i]
	var icon_bg: ColorRect    = _icon_bgs[i]
	var icon_tex: TextureRect = _icon_textures[i]
	var name_lbl: Label       = _name_labels[i]
	var cnt_lbl: Label        = _count_labels[i]
	var border: ColorRect     = _borders[i]
	var desc: Dictionary      = _slots[i]
	var is_hotbar: bool       = (str(desc.get("type", "")) == "hotbar")
	var is_active: bool       = (is_hotbar and int(desc.get("index", -1)) == active_index)

	if stack.is_empty():
		panel.color        = COLOR_ACTIVE if is_active else COLOR_BG_EMPTY
		icon_bg.color      = Color.TRANSPARENT
		icon_tex.texture   = null
		name_lbl.text      = ""
		cnt_lbl.text       = ""
	else:
		panel.color = COLOR_ACTIVE if is_active else COLOR_BG_FILLED
		var item_id: String = str(stack.get("id", ""))
		var def = ItemRegistry.resolve(item_id)
		if def != null and def.icon_atlas != Vector2i(-1, -1):
			icon_bg.color    = Color.TRANSPARENT
			var atlas_tex    := AtlasTexture.new()
			atlas_tex.atlas  = ITEM_ICON_ATLAS
			atlas_tex.region = Rect2(
				def.icon_atlas.x * ICON_TILE_PX,
				def.icon_atlas.y * ICON_TILE_PX,
				ICON_TILE_PX, ICON_TILE_PX)
			icon_tex.texture = atlas_tex
		elif def != null:
			icon_bg.color    = def.icon_color
			icon_tex.texture = null
		else:
			icon_bg.color    = Color(0.35, 0.35, 0.35)
			icon_tex.texture = null
		# Name: use display_name, truncated to fit. Show first word if long.
		var display: String = def.display_name if def != null else item_id
		name_lbl.text = display
		var cnt: int = int(stack.get("count", 1))
		cnt_lbl.text = str(cnt) if cnt > 1 else ""

	# Border highlight for active slot
	if is_active:
		border.color = COLOR_ACTIVE_BORDER
	else:
		var t: String = str(desc.get("type", ""))
		match t:
			"tool":     border.color = COLOR_BORDER_TOOL
			"weapon":   border.color = COLOR_BORDER_WEAPON
			"talisman": border.color = COLOR_BORDER_TALISM
			_:          border.color = COLOR_BORDER_NORMAL

# ---------------------------------------------------------------------------
# Active slot management
# ---------------------------------------------------------------------------

func _set_active(i: int) -> void:
	i = clampi(i, 0, HOTBAR_SLOTS - 1)
	active_index = i
	if is_instance_valid(EventLog):
		var stack: Dictionary = {} if inventory == null else inventory.bag[i] as Dictionary
		EventLog.record("hotbar_select", {"index": i, "id": str(stack.get("id", ""))})
	# Sync inventory.active_tool_index so Player.gd's get_active_tool() fallback
	# and appearance update see the correct tool when bag[i] is a tool item.
	if inventory != null:
		var stack: Dictionary = inventory.bag[active_index] as Dictionary
		if str(stack.get("category", "")) == "tool":
			# Find which tool slot holds the same id, or default 0
			var tid: String = str(stack.get("id", ""))
			for ti in range(inventory.TOOL_SLOT_COUNT):
				var ts: Dictionary = inventory.tool_slots[ti] as Dictionary
				if str(ts.get("id", "")) == tid:
					inventory.active_tool_index = ti
					break
	refresh()

# ---------------------------------------------------------------------------
# Expanded panel toggle
# ---------------------------------------------------------------------------

func _toggle_expanded() -> void:
	# Cancel any in-flight drag on close
	if _expanded_visible and _drag_origin >= 0:
		_cancel_drag()
	_expanded_visible = not _expanded_visible
	_expanded_bg.visible = _expanded_visible
	for i in range(_slots.size()):
		var t: String = str(_slots[i].get("type", ""))
		if t != "hotbar":
			_panels[i].visible = _expanded_visible
	refresh()

# ---------------------------------------------------------------------------
# Drag & drop
# ---------------------------------------------------------------------------

func _start_drag(slot_i: int) -> void:
	var stack: Dictionary = _get_slot_stack(slot_i)
	if stack.is_empty():
		return
	_drag_stack  = stack.duplicate()
	_drag_origin = slot_i
	_set_slot_stack(slot_i, {})
	_drag_cursor.visible = true
	_sync_drag_cursor_icon(_drag_stack)
	refresh()

func _drop_on_slot(slot_i: int) -> void:
	# Place dragged stack onto target slot; swap if occupied
	var target: Dictionary = _get_slot_stack(slot_i)
	_set_slot_stack(slot_i, _drag_stack)
	if not target.is_empty():
		_set_slot_stack(_drag_origin, target)
	_end_drag()

func _place_one_on_slot(slot_i: int) -> void:
	# Place exactly one unit of dragged stack onto slot
	var target: Dictionary = _get_slot_stack(slot_i)
	var drag_id: String = str(_drag_stack.get("id", ""))
	var drag_count: int = int(_drag_stack.get("count", 1))
	if target.is_empty():
		var one: Dictionary = _drag_stack.duplicate()
		one["count"] = 1
		_set_slot_stack(slot_i, one)
		drag_count -= 1
	elif str(target.get("id", "")) == drag_id:
		target["count"] = int(target.get("count", 0)) + 1
		_set_slot_stack(slot_i, target)
		drag_count -= 1
	else:
		# Different item — full swap instead
		_drop_on_slot(slot_i)
		return
	if drag_count <= 0:
		_end_drag()
	else:
		_drag_stack["count"] = drag_count
		_sync_drag_cursor_icon(_drag_stack)
		_set_slot_stack(_drag_origin, {})  # origin stays empty while dragging remainder
		refresh()

func _start_split(slot_i: int) -> void:
	# Take half (rounded up) from slot into drag
	var stack: Dictionary = _get_slot_stack(slot_i)
	if stack.is_empty():
		return
	var total: int = int(stack.get("count", 1))
	var take: int  = max(1, (total + 1) / 2)
	var leave: int = total - take
	_drag_stack  = stack.duplicate()
	_drag_stack["count"] = take
	_drag_origin = slot_i
	if leave <= 0:
		_set_slot_stack(slot_i, {})
	else:
		var remainder := stack.duplicate()
		remainder["count"] = leave
		_set_slot_stack(slot_i, remainder)
	_drag_cursor.visible = true
	_sync_drag_cursor_icon(_drag_stack)
	refresh()

## Sync the drag cursor's icon and count to match the given stack.
func _sync_drag_cursor_icon(stack: Dictionary) -> void:
	var drag_icon_bg  := _drag_cursor.get_node_or_null("IconBg")  as ColorRect
	var drag_icon_tex := _drag_cursor.get_node_or_null("IconTex") as TextureRect
	var item_id: String = str(stack.get("id", ""))
	var def = ItemRegistry.resolve(item_id)
	if drag_icon_bg != null and drag_icon_tex != null:
		if def != null and def.icon_atlas != Vector2i(-1, -1):
			drag_icon_bg.color = Color.TRANSPARENT
			var atlas_tex := AtlasTexture.new()
			atlas_tex.atlas  = ITEM_ICON_ATLAS
			atlas_tex.region = Rect2(
				def.icon_atlas.x * ICON_TILE_PX,
				def.icon_atlas.y * ICON_TILE_PX,
				ICON_TILE_PX, ICON_TILE_PX)
			drag_icon_tex.texture = atlas_tex
		elif def != null:
			drag_icon_bg.color    = def.icon_color
			drag_icon_tex.texture = null
		else:
			drag_icon_bg.color    = COLOR_DRAG_CURSOR
			drag_icon_tex.texture = null
	var cnt: int = int(stack.get("count", 1))
	_drag_cursor_lbl.text = str(cnt) if cnt > 1 else ""

func _cancel_drag() -> void:
	if _drag_origin < 0:
		return
	# Return stack to origin (merge with whatever is there)
	var current: Dictionary = _get_slot_stack(_drag_origin)
	if current.is_empty():
		_set_slot_stack(_drag_origin, _drag_stack)
	else:
		# Try to merge counts if same id
		if str(current.get("id", "")) == str(_drag_stack.get("id", "")):
			current["count"] = int(current.get("count", 0)) + int(_drag_stack.get("count", 1))
			_set_slot_stack(_drag_origin, current)
		else:
			# Find first empty slot to dump
			for i in range(_slots.size()):
				if _get_slot_stack(i).is_empty():
					_set_slot_stack(i, _drag_stack)
					break
	_end_drag()

func _end_drag() -> void:
	_drag_stack  = {}
	_drag_origin = -1
	_drag_cursor.visible = false
	refresh()

# ---------------------------------------------------------------------------
# Hit test — return slot index under a canvas-space point, or -1
# ---------------------------------------------------------------------------
func _slot_at_point(pt: Vector2) -> int:
	for i in range(_panels.size()):
		var p: ColorRect = _panels[i]
		if not p.visible:
			continue
		var r := Rect2(p.position, p.size)
		if r.has_point(pt):
			return i
	return -1

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Number keys 1–8 (hotbar active slot)
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
			KEY_TAB, KEY_I:
				_toggle_expanded()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if _drag_origin >= 0:
					_cancel_drag()
					get_viewport().set_input_as_handled()
				elif _expanded_visible:
					_toggle_expanded()
					get_viewport().set_input_as_handled()

	# Scroll wheel cycles active hotbar slot
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_active((active_index - 1 + HOTBAR_SLOTS) % HOTBAR_SLOTS)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_active((active_index + 1) % HOTBAR_SLOTS)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var pt: Vector2 = event.position
			var si: int = _slot_at_point(pt)
			if si >= 0:
				if _drag_origin < 0:
					_start_drag(si)
				else:
					_drop_on_slot(si)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var pt: Vector2 = event.position
			var si: int = _slot_at_point(pt)
			if si >= 0:
				if _drag_origin < 0:
					_start_split(si)
				else:
					_place_one_on_slot(si)
				get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# Process: refresh display + bars + drag cursor position
# ---------------------------------------------------------------------------

var _frame_counter: int = 0

func _process(_delta: float) -> void:
	# Move drag cursor to mouse position
	if _drag_cursor.visible:
		var mp: Vector2 = get_viewport().get_mouse_position()
		_drag_cursor.position = mp - Vector2(SLOT_SIZE / 2, SLOT_SIZE / 2)

	_frame_counter += 1
	if _frame_counter >= 6:
		_frame_counter = 0
		refresh()
		_refresh_bars()

func _refresh_bars() -> void:
	if player == null or _hp_bar_fill == null:
		return
	var health_node = player.get_node_or_null("Health")
	if health_node != null:
		var frac: float = float(health_node.get("current_hp")) / float(health_node.get("max_hp"))
		frac = clampf(frac, 0.0, 1.0)
		_hp_bar_fill.size.x = _bar_total_width * frac
	var max_food: int = int(player.get("max_food")) if player.get("max_food") else 100
	var food: int = int(player.get("food")) if player.get("food") != null else 0
	var food_frac: float = clampf(float(food) / float(max_food), 0.0, 1.0)
	_food_bar_fill.size.x = _bar_total_width * food_frac
