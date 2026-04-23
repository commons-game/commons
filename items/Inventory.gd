## Inventory — slot management for the player's item loadout.
##
## Layout:
##   weapon_slot       — fixed, weapon category only
##   talisman_slot     — fixed, talisman category only; has dormant/awakened state
##   tool_slots[2]     — free, tool category only
##   gear_slots        — { helmet, chest, legs, shoes } — armor only
##   bag[BAG_SIZE]     — any category; supports stacking up to stack_max
##
## An ItemStack is a Dictionary:
##   { "id": String, "count": int, "category": String }
##   optionally: { ..., "equipment_slot": String } for armor
## An empty slot is {}.
extends RefCounted

const BAG_SIZE := 12
const TOOL_SLOT_COUNT := 2
const GEAR_SLOT_NAMES := ["helmet", "chest", "legs", "shoes"]

var weapon_slot: Dictionary = {}
var talisman_slot: Dictionary = {}
var talisman_awakened: bool = false
var tool_slots: Array = [{}, {}]
var active_tool_index: int = 0
var gear_slots: Dictionary = {
	"helmet": {}, "chest": {}, "legs": {}, "shoes": {}
}
var bag: Array = []  # length = BAG_SIZE, each entry is {} or ItemStack

func _init() -> void:
	bag.resize(BAG_SIZE)
	for i in range(BAG_SIZE):
		bag[i] = {}

# ---------------------------------------------------------------------------
# Bag
# ---------------------------------------------------------------------------

func is_bag_empty() -> bool:
	for i in range(BAG_SIZE):
		if not (bag[i] as Dictionary).is_empty():
			return false
	return true

func is_bag_full() -> bool:
	for i in range(BAG_SIZE):
		if (bag[i] as Dictionary).is_empty():
			return false
	return true

## Add an item stack to the bag. stack_max controls merging.
## Returns false if the bag is full and no merge was possible.
func add_to_bag(stack: Dictionary, stack_max: int = 1) -> bool:
	var id: String = str(stack.get("id", ""))
	var count: int = int(stack.get("count", 1))

	# Try to merge into an existing stack of the same item.
	if stack_max > 1:
		for i in range(BAG_SIZE):
			var slot: Dictionary = bag[i] as Dictionary
			if slot.is_empty():
				continue
			if str(slot.get("id", "")) != id:
				continue
			var existing: int = int(slot.get("count", 0))
			if existing < stack_max:
				var can_add := stack_max - existing
				var adding := mini(count, can_add)
				slot["count"] = existing + adding
				count -= adding
				if count <= 0:
					return true

	# Place remaining count in an empty slot.
	while count > 0:
		var placed := false
		for i in range(BAG_SIZE):
			if (bag[i] as Dictionary).is_empty():
				var placing := mini(count, stack_max)
				bag[i] = {"id": id, "count": placing,
					"category": str(stack.get("category", ""))}
				count -= placing
				placed = true
				break
		if not placed:
			return false

	return true

## Remove count units of item_id from the bag.
## Returns false if there aren't enough units.
func remove_from_bag(item_id: String, count: int) -> bool:
	if bag_stack_total(item_id) < count:
		return false
	var remaining := count
	for i in range(BAG_SIZE):
		var slot: Dictionary = bag[i] as Dictionary
		if slot.is_empty() or str(slot.get("id", "")) != item_id:
			continue
		var in_slot: int = int(slot.get("count", 0))
		if in_slot <= remaining:
			remaining -= in_slot
			bag[i] = {}
		else:
			slot["count"] = in_slot - remaining
			remaining = 0
		if remaining <= 0:
			break
	return true

## Number of distinct bag slots containing item_id.
func bag_count(item_id: String) -> int:
	var n := 0
	for i in range(BAG_SIZE):
		var slot: Dictionary = bag[i] as Dictionary
		if not slot.is_empty() and str(slot.get("id", "")) == item_id:
			n += 1
	return n

## Total units of item_id across all bag slots.
func bag_stack_total(item_id: String) -> int:
	var total := 0
	for i in range(BAG_SIZE):
		var slot: Dictionary = bag[i] as Dictionary
		if not slot.is_empty() and str(slot.get("id", "")) == item_id:
			total += int(slot.get("count", 0))
	return total

# ---------------------------------------------------------------------------
# Weapon slot
# ---------------------------------------------------------------------------

func equip_weapon(stack: Dictionary) -> bool:
	if str(stack.get("category", "")) != "weapon":
		return false
	weapon_slot = stack.duplicate()
	return true

func unequip_weapon() -> void:
	if weapon_slot.is_empty():
		return
	add_to_bag(weapon_slot, 1)
	weapon_slot = {}

# ---------------------------------------------------------------------------
# Talisman slot
# ---------------------------------------------------------------------------

func equip_talisman(stack: Dictionary) -> bool:
	if str(stack.get("category", "")) != "talisman":
		return false
	talisman_slot = stack.duplicate()
	talisman_awakened = false
	return true

func unequip_talisman() -> void:
	if talisman_slot.is_empty():
		return
	talisman_awakened = false
	add_to_bag(talisman_slot, 1)
	talisman_slot = {}

## Toggle dormant/awakened state of the equipped talisman.
## Returns the new awakened state. Returns false if no talisman equipped.
func toggle_talisman() -> bool:
	if talisman_slot.is_empty():
		return false
	talisman_awakened = not talisman_awakened
	return talisman_awakened

# ---------------------------------------------------------------------------
# Tool slots
# ---------------------------------------------------------------------------

## Select the active tool slot (0 or 1). Out-of-range values are ignored.
func select_tool(index: int) -> void:
	if index >= 0 and index < TOOL_SLOT_COUNT:
		active_tool_index = index
		if is_instance_valid(EventLog):
			EventLog.record("tool_select", {
				"index": index,
				"id": str(tool_slots[index].get("id", "")),
			})

## Return the ItemStack in the currently active tool slot, or {} if empty.
func get_active_tool() -> Dictionary:
	return tool_slots[active_tool_index] as Dictionary

func set_tool_slot(index: int, stack: Dictionary) -> bool:
	if index < 0 or index >= TOOL_SLOT_COUNT:
		return false
	var cat: String = str(stack.get("category", ""))
	if cat != "tool" and cat != "structure":
		return false
	tool_slots[index] = stack.duplicate()
	return true

func clear_tool_slot(index: int) -> void:
	if index >= 0 and index < TOOL_SLOT_COUNT:
		tool_slots[index] = {}

# ---------------------------------------------------------------------------
# Gear slots
# ---------------------------------------------------------------------------

func equip_gear(stack: Dictionary) -> bool:
	if str(stack.get("category", "")) != "armor":
		return false
	var slot_name: String = str(stack.get("equipment_slot", ""))
	if not GEAR_SLOT_NAMES.has(slot_name):
		return false
	gear_slots[slot_name] = stack.duplicate()
	return true

func unequip_gear(slot_name: String) -> void:
	if not GEAR_SLOT_NAMES.has(slot_name):
		return
	var slot: Dictionary = gear_slots[slot_name] as Dictionary
	if slot.is_empty():
		return
	add_to_bag(slot, 1)
	gear_slots[slot_name] = {}

# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var bag_arr: Array = []
	for i in range(BAG_SIZE):
		bag_arr.append((bag[i] as Dictionary).duplicate())
	var tools_arr: Array = []
	for i in range(TOOL_SLOT_COUNT):
		tools_arr.append((tool_slots[i] as Dictionary).duplicate())
	var gear_copy: Dictionary = {}
	for s in GEAR_SLOT_NAMES:
		gear_copy[s] = (gear_slots[s] as Dictionary).duplicate()
	return {
		"weapon_slot":       weapon_slot.duplicate(),
		"talisman_slot":     talisman_slot.duplicate(),
		"talisman_awakened": talisman_awakened,
		"active_tool_index": active_tool_index,
		"tool_slots":        tools_arr,
		"gear_slots":        gear_copy,
		"bag":               bag_arr,
	}

func from_dict(data: Dictionary) -> void:
	weapon_slot        = (data.get("weapon_slot",   {}) as Dictionary).duplicate()
	talisman_slot      = (data.get("talisman_slot",  {}) as Dictionary).duplicate()
	talisman_awakened  = bool(data.get("talisman_awakened", false))
	active_tool_index  = int(data.get("active_tool_index", 0))

	var tools = data.get("tool_slots", [{}, {}])
	for i in range(TOOL_SLOT_COUNT):
		tool_slots[i] = ((tools[i] if i < tools.size() else {}) as Dictionary).duplicate()

	var gear = data.get("gear_slots", {})
	for s in GEAR_SLOT_NAMES:
		gear_slots[s] = ((gear.get(s, {})) as Dictionary).duplicate()

	var bag_data = data.get("bag", [])
	for i in range(BAG_SIZE):
		bag[i] = ((bag_data[i] if i < bag_data.size() else {}) as Dictionary).duplicate()
