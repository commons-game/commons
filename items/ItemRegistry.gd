## ItemRegistry — maps item id strings to ItemDefinition objects.
##
## Register built-in items in _ready(). Mods can call register() to add more.
## Everything else calls ItemRegistry.resolve(id) to look up definitions.
extends Node

const ItemDefinitionScript := preload("res://items/ItemDefinition.gd")

var _entries: Dictionary = {}  # id (String) -> ItemDefinition

func _ready() -> void:
	_register_builtins()

func register(def: Object) -> void:
	_entries[def.id] = def

func resolve(item_id: String) -> Object:
	return _entries.get(item_id, null)

func has_item(item_id: String) -> bool:
	return _entries.has(item_id)

func _make(id: String, category: String, display_name: String,
		stack_max: int = 1, equipment_slot: String = "") -> Object:
	var d = ItemDefinitionScript.new()
	d.id             = id
	d.category       = category
	d.display_name   = display_name
	d.stack_max      = stack_max
	d.equipment_slot = equipment_slot
	return d

func _register_builtins() -> void:
	# --- Tools ---
	register(_make("lantern",        "tool", "Lantern"))
	register(_make("hammer",         "tool", "Hammer"))
	register(_make("shovel",         "tool", "Shovel"))
	register(_make("wooden_axe",     "tool", "Wooden Axe"))
	register(_make("wooden_pickaxe", "tool", "Wooden Pickaxe"))

	# --- Weapons ---
	register(_make("iron_sword",  "weapon",  "Iron Sword"))

	# --- Talismans ---
	register(_make("talisman_of_chaos",  "talisman", "Talisman of Chaos"))
	register(_make("ward_of_solitude",   "talisman", "Ward of Solitude"))
	register(_make("compass_of_lost",    "talisman", "Compass of the Lost"))

	# --- Armor ---
	register(_make("leather_helmet", "armor", "Leather Helmet", 1, "helmet"))
	register(_make("leather_chest",  "armor", "Leather Chest",  1, "chest"))
	register(_make("leather_legs",   "armor", "Leather Legs",   1, "legs"))
	register(_make("leather_shoes",  "armor", "Leather Shoes",  1, "shoes"))

	# --- Materials (stackable) ---
	register(_make("wood",  "material", "Wood",  32))
	register(_make("stone", "material", "Stone", 32))

	# --- Stone tools ---
	register(_make("stone_axe",     "tool", "Stone Axe"))
	register(_make("stone_pickaxe", "tool", "Stone Pickaxe"))

	# --- Structures (placed in the world) ---
	register(_make("campfire",  "structure", "Campfire",  1))
	register(_make("workbench", "structure", "Workbench", 1))
