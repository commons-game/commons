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

## icon_atlas: atlas tile coords for a world-tile crop icon; Vector2i(-1,-1) = none.
func _make(id: String, category: String, display_name: String,
		stack_max: int = 1, equipment_slot: String = "",
		icon_color: Color = Color(0.35, 0.35, 0.35),
		icon_atlas: Vector2i = Vector2i(-1, -1)) -> Object:
	var d = ItemDefinitionScript.new()
	d.id             = id
	d.category       = category
	d.display_name   = display_name
	d.stack_max      = stack_max
	d.equipment_slot = equipment_slot
	d.icon_color     = icon_color
	d.icon_atlas     = icon_atlas
	return d

func _register_builtins() -> void:
	# --- Tools ---
	# Atlas row 0 = ground tiles, row 1 = objects (tree, rock, …). Tools have no
	# world-tile art yet — give each a distinct colour so they're visually distinct.
	register(_make("flint_knife",     "tool", "Flint Knife",     1, "", Color(0.48, 0.46, 0.35)))
	register(_make("stone_axe",      "tool", "Stone Axe",      1, "", Color(0.52, 0.52, 0.55)))
	register(_make("stone_pickaxe",  "tool", "Stone Pickaxe",  1, "", Color(0.48, 0.52, 0.58)))
	register(_make("wooden_axe",     "tool", "Wooden Axe",     1, "", Color(0.65, 0.48, 0.28)))
	register(_make("wooden_pickaxe", "tool", "Wooden Pickaxe", 1, "", Color(0.60, 0.48, 0.32)))
	register(_make("lantern",        "tool", "Lantern",        1, "", Color(0.92, 0.78, 0.22)))
	register(_make("hammer",         "tool", "Hammer",         1, "", Color(0.42, 0.45, 0.50)))
	register(_make("shovel",         "tool", "Shovel",         1, "", Color(0.52, 0.46, 0.32)))

	# --- Weapons ---
	register(_make("iron_sword",  "weapon",  "Iron Sword",  1, "", Color(0.75, 0.75, 0.80)))

	# --- Talismans ---
	register(_make("talisman_of_chaos", "talisman", "Talisman of Chaos",  1, "", Color(0.78, 0.18, 0.85)))
	register(_make("ward_of_solitude",  "talisman", "Ward of Solitude",   1, "", Color(0.18, 0.28, 0.82)))
	register(_make("compass_of_lost",   "talisman", "Compass of the Lost",1, "", Color(0.88, 0.78, 0.15)))

	# --- Armor ---
	var leather := Color(0.58, 0.42, 0.22)
	register(_make("leather_helmet", "armor", "Leather Helmet", 1, "helmet", leather))
	register(_make("leather_chest",  "armor", "Leather Chest",  1, "chest",  leather))
	register(_make("leather_legs",   "armor", "Leather Legs",   1, "legs",   leather))
	register(_make("leather_shoes",  "armor", "Leather Shoes",  1, "shoes",  leather))

	# --- Materials (stackable) ---
	# wood / stone / ether_crystal reuse their world-tile atlas art for a free icon.
	# Atlas: row 0 = ground, row 1 = objects. wood→tree(0,1), stone→rock(1,1).
	register(_make("wood",         "material", "Wood",          32, "", Color(0.65, 0.48, 0.25), Vector2i(0, 1)))
	register(_make("stone",        "material", "Stone",         32, "", Color(0.55, 0.55, 0.55), Vector2i(1, 1)))
	register(_make("reeds",        "material", "Reeds",         32, "", Color(0.40, 0.70, 0.30), Vector2i(4, 1)))
	register(_make("ether_crystal","material", "Ether Crystal", 16, "", Color(0.30, 0.80, 0.75), Vector2i(3, 2)))
	# Tier-3 deep-biome materials (placeholder — Bloom/Still identity colours).
	register(_make("marrow",       "material", "Marrow",        10, "", Color(0.65, 0.12, 0.18)))  # deep Bloom crimson — drops from Wisp (Bloom night mob)
	register(_make("sinter",       "material", "Sinter",        10, "", Color(0.55, 0.72, 0.88)))  # Still ice blue
	register(_make("moonstone",    "material", "Moonstone",     10, "", Color(0.82, 0.88, 0.98)))  # pale cold white — crystallises in Hollow at night

	# --- Food ---
	register(_make("berry", "food", "Berry", 32, "", Color(0.88, 0.22, 0.28)))

	# --- Structures (placed in the world) ---
	register(_make("campfire",  "structure", "Campfire",  1, "", Color(0.92, 0.52, 0.12)))  # orange flame
	register(_make("workbench", "structure", "Workbench", 1, "", Color(0.52, 0.38, 0.18)))
	register(_make("bedroll",   "structure", "Bedroll",   1, "", Color(0.68, 0.52, 0.50)))
	register(_make("tether",    "structure", "Tether",    1, "", Color(0.58, 0.72, 0.88)))  # pale Still blue
	register(_make("shrine",    "structure", "Shrine",    1, "", Color(0.52, 0.28, 0.72)))  # Bloom/Still purple

	# --- Shrine-gate materials (placeholder — no drop sources yet) ---
	register(_make("mass_core",    "material", "Mass Core",    5, "", Color(0.60, 0.08, 0.15)))  # Bloom boss
	register(_make("form_crystal", "material", "Form Crystal", 5, "", Color(0.65, 0.85, 0.95)))  # Still boss
	register(_make("ichor",        "material", "Ichor",        5, "", Color(0.15, 0.82, 0.42)))  # pure Bloom
	register(_make("cipher",       "material", "Cipher",       5, "", Color(0.88, 0.78, 0.18)))  # pure Still gold
