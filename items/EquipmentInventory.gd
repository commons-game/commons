## EquipmentInventory — tracks equipped items + bag for the equipment system.
##
## Handles the 4 visual character slots: armor, head, feet, held_item.
##
## Bag entries are {"id": String, "slot": String}. The slot is stored
## alongside the item_id so equip() can work without a live registry reference.
## Callers should pass the slot when calling add_to_bag().
##
## Usage:
##   const EquipmentInventoryScript := preload("res://items/EquipmentInventory.gd")
##   const EquipmentRegistryScript  := preload("res://items/EquipmentRegistry.gd")
##   var eq = EquipmentInventoryScript.new()
##   var slot = EquipmentRegistryScript.get_slot("bone_armor")
##   eq.add_to_bag("bone_armor", slot)
##   eq.equip("bone_armor")
extends RefCounted

const BAG_SIZE := 12
const VALID_SLOTS := ["armor", "head", "feet", "held_item"]

var _equipped: Dictionary = {
	"armor":     "",
	"head":      "",
	"feet":      "",
	"held_item": "",
}

## Each entry is "" (empty) or Dictionary {"id": String, "slot": String}.
var _bag: Array = []

func _init() -> void:
	_bag.resize(BAG_SIZE)
	for i in range(BAG_SIZE):
		_bag[i] = ""

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _is_empty_slot(entry) -> bool:
	if entry == null:
		return true
	if entry is Dictionary:
		return str((entry as Dictionary).get("id", "")) == ""
	if entry is String:
		return (entry as String) == ""
	return false

func _entry_id(entry) -> String:
	if entry is Dictionary:
		return str((entry as Dictionary).get("id", ""))
	if entry is String:
		return entry as String
	return ""

func _entry_slot(entry) -> String:
	if entry is Dictionary:
		return str((entry as Dictionary).get("slot", ""))
	return ""

# ---------------------------------------------------------------------------
# Bag
# ---------------------------------------------------------------------------

## Add item_id to the first empty bag slot.
## Pass the item's equipment slot so equip() works without an external registry.
## Returns false if the bag is full.
func add_to_bag(item_id: String, slot: String = "") -> bool:
	for i in range(BAG_SIZE):
		if _is_empty_slot(_bag[i]):
			_bag[i] = {"id": item_id, "slot": slot}
			return true
	return false

## Return the bag contents as an Array of item_id Strings ("" = empty slot).
func get_bag() -> Array:
	var result: Array = []
	for i in range(BAG_SIZE):
		result.append(_entry_id(_bag[i]))
	return result

# ---------------------------------------------------------------------------
# Equipping / unequipping
# ---------------------------------------------------------------------------

## Move item_id from the bag to its equipment slot.
## The slot is read from the bag entry (stored at add_to_bag time).
## Returns false if the item is not in the bag or slot is unknown.
func equip(item_id: String) -> bool:
	# Find item in bag
	var bag_index := -1
	for i in range(BAG_SIZE):
		if _entry_id(_bag[i]) == item_id:
			bag_index = i
			break
	if bag_index == -1:
		return false

	var slot: String = _entry_slot(_bag[bag_index])
	if slot.is_empty() or not VALID_SLOTS.has(slot):
		return false

	# If something is already in that slot, push it back to the bag first.
	var current: String = str(_equipped.get(slot, ""))
	if current != "":
		# Find an empty bag slot (other than bag_index) to hold the displaced item.
		# If none exists, use bag_index itself (we're clearing it for the new item).
		var displaced_slot := -1
		for i in range(BAG_SIZE):
			if i == bag_index:
				continue
			if _is_empty_slot(_bag[i]):
				displaced_slot = i
				break
		var current_slot: String = str(_equipped.get(slot, ""))
		if displaced_slot == -1:
			# Use bag_index to hold the displaced item
			# Note: we need to know displaced item's slot — search equipped slots
			var displaced_item_slot := _find_slot_for_equipped(current)
			_bag[bag_index] = {"id": current, "slot": displaced_item_slot}
		else:
			var displaced_item_slot := _find_slot_for_equipped(current)
			_bag[displaced_slot] = {"id": current, "slot": displaced_item_slot}
			_bag[bag_index] = ""

	else:
		_bag[bag_index] = ""

	_equipped[slot] = item_id
	return true

## Find which slot an item currently occupies in _equipped.
func _find_slot_for_equipped(item_id: String) -> String:
	for slot in VALID_SLOTS:
		if str(_equipped.get(slot, "")) == item_id:
			return slot
	return ""

## Move the item in slot back to the first empty bag slot.
## Returns false if slot is empty or bag is full.
func unequip(slot: String) -> bool:
	if not VALID_SLOTS.has(slot):
		return false
	var item_id: String = str(_equipped.get(slot, ""))
	if item_id == "":
		return false
	for i in range(BAG_SIZE):
		if _is_empty_slot(_bag[i]):
			_bag[i] = {"id": item_id, "slot": slot}
			_equipped[slot] = ""
			return true
	return false

## Return the item_id equipped in slot, or "" if empty.
func get_equipped(slot: String) -> String:
	return str(_equipped.get(slot, ""))

# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var bag_copy: Array = []
	for i in range(BAG_SIZE):
		var entry = _bag[i]
		if entry is Dictionary:
			bag_copy.append((entry as Dictionary).duplicate())
		else:
			bag_copy.append("")
	return {
		"equipped": _equipped.duplicate(),
		"bag":      bag_copy,
	}

func from_dict(d: Dictionary) -> void:
	var eq = d.get("equipped", {})
	if eq is Dictionary:
		for slot in VALID_SLOTS:
			_equipped[slot] = str((eq as Dictionary).get(slot, ""))
	var bag_data = d.get("bag", [])
	for i in range(BAG_SIZE):
		var raw = null
		if bag_data is Array and i < (bag_data as Array).size():
			raw = (bag_data as Array)[i]
		if raw is Dictionary:
			_bag[i] = (raw as Dictionary).duplicate()
		elif raw is String and (raw as String) != "":
			_bag[i] = {"id": raw as String, "slot": ""}
		else:
			_bag[i] = ""
