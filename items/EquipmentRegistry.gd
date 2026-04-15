## EquipmentRegistry — static registry mapping item_id → item dict.
##
## Separate from the existing ItemRegistry (Node autoload for action-bar items).
## This registry is purely static and handles equipment-system items.
##
## Usage:
##   const EquipmentRegistry := preload("res://items/EquipmentRegistry.gd")
##   EquipmentRegistry.register({"id": "bone_armor", "slot": "armor", ...})
##   var d: Dictionary = EquipmentRegistry.get_item("bone_armor")
##   var slot: String = EquipmentRegistry.get_slot("bone_armor")
extends RefCounted

## item_id (String) → item dict (Dictionary)
static var _items: Dictionary = {}

## Register an item dict. Overwrites any previous registration with the same id.
static func register(item_dict: Dictionary) -> void:
	var item_id: String = str(item_dict.get("id", ""))
	if item_id.is_empty():
		push_error("EquipmentRegistry.register: item_dict missing 'id' field")
		return
	_items[item_id] = item_dict.duplicate(true)

## Return the registered item dict for item_id, or {} if not found.
static func get_item(item_id: String) -> Dictionary:
	if _items.has(item_id):
		return (_items[item_id] as Dictionary).duplicate(true)
	return {}

## Return the equipment slot for item_id, or "" if not registered.
static func get_slot(item_id: String) -> String:
	if not _items.has(item_id):
		return ""
	return str((_items[item_id] as Dictionary).get("slot", ""))

## Clear all registrations (used in tests for isolation).
static func reset() -> void:
	_items.clear()
