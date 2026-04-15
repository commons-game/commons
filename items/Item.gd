## Item — lightweight data class for equipment items.
##
## Represents a single item type that can be equipped in a character slot.
## Distinct from ItemDefinition (which is used by the Inventory/action-bar system).
##
## Usage:
##   const ItemScript := preload("res://items/Item.gd")
##   var item = ItemScript.new()
##   item.parse({"id": "bone_armor", "slot": "armor", "display_name": "Bone Armor",
##               "stats": {"defense_modifier": 1.3}})
extends RefCounted

## Unique identifier string.
var id: String = ""

## Which character slot this item occupies.
## One of: "armor" | "head" | "feet" | "held_item"
var slot: String = ""

## Human-readable name shown in the UI.
var display_name: String = ""

## Stat modifiers this item applies when equipped.
## e.g. {"defense_modifier": 1.2, "speed_modifier": 0.9}
var stats: Dictionary = {}

## Populate from a Dictionary (instance method to avoid static factory gotcha).
## Call as: var item = ItemScript.new(); item.parse(d)
func parse(d: Dictionary) -> void:
	id           = str(d.get("id", ""))
	slot         = str(d.get("slot", ""))
	display_name = str(d.get("display_name", id))
	var raw = d.get("stats", {})
	if raw is Dictionary:
		stats = (raw as Dictionary).duplicate()
	else:
		stats = {}

func to_dict() -> Dictionary:
	return {
		"id":           id,
		"slot":         slot,
		"display_name": display_name,
		"stats":        stats.duplicate(),
	}
