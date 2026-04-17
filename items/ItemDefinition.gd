## ItemDefinition — describes a type of item.
##
## Categories:
##   "weapon"   — goes in the fixed weapon slot on the action bar
##   "talisman" — goes in the fixed talisman slot on the action bar
##   "tool"     — goes in the free tool slots on the action bar
##   "armor"    — goes in a passive gear slot (set equipment_slot)
##   "material" — stackable resource that lives in the bag
##
## Usage:
##   var d := ItemDefinitionScript.new()
##   d.id = "hammer"
##   d.category = "tool"
##   d.display_name = "Iron Hammer"
extends RefCounted

var id: String = ""
var category: String = ""
var equipment_slot: String = ""  # "helmet"|"chest"|"legs"|"shoes" for armor; "" otherwise
var stack_max: int = 1

var display_name: String = "":
	get:
		return display_name if display_name != "" else id
	set(value):
		display_name = value

## Icon color shown in hotbar/inventory when no atlas tile is available.
var icon_color: Color = Color(0.35, 0.35, 0.35)
## Atlas tile coords for this item's icon (from the main tileset).
## Vector2i(-1,-1) = no atlas icon, fall back to icon_color.
var icon_atlas: Vector2i = Vector2i(-1, -1)

func is_weapon() -> bool:
	return category == "weapon"

func is_talisman() -> bool:
	return category == "talisman"

func is_tool() -> bool:
	return category == "tool"

func is_armor() -> bool:
	return category == "armor"

func is_material() -> bool:
	return category == "material"

func to_dict() -> Dictionary:
	return {
		"id":             id,
		"category":       category,
		"equipment_slot": equipment_slot,
		"stack_max":      stack_max,
		"display_name":   display_name,
	}

func from_dict(data: Dictionary) -> void:
	id             = str(data.get("id", ""))
	category       = str(data.get("category", ""))
	equipment_slot = str(data.get("equipment_slot", ""))
	stack_max      = int(data.get("stack_max", 1))
	display_name   = str(data.get("display_name", ""))
