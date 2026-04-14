## ModBundle — parsed representation of a mod's definition file.
## Load via load_from_json(). Access defs via tile_defs, entity_defs, etc.
class_name ModBundle

const TileDefScript := preload("res://mods/data/TileDef.gd")
const BuffDefScript := preload("res://mods/data/BuffDef.gd")

var tile_defs: Dictionary = {}    # String id -> TileDef
var entity_defs: Dictionary = {}  # String id -> EntityDef (Phase 2+)
var item_defs: Dictionary = {}    # String id -> ItemDef (Phase 2+)
var buff_defs: Dictionary = {}    # String id -> BuffDef

func load_from_json(json_string: String) -> void:
	var payload = JSON.parse_string(json_string)
	if payload == null or not payload is Dictionary:
		push_warning("ModBundle: invalid JSON — returning empty bundle")
		return
	_parse_tiles(payload.get("tiles", []))
	_parse_buffs(payload.get("buffs", []))

func _parse_tiles(arr: Array) -> void:
	for d in arr:
		if not d is Dictionary or not d.has("id") or d["id"] == "":
			push_warning("ModBundle: skipping tile def with missing id")
			continue
		var td = TileDefScript.new()
		td.parse(d)
		tile_defs[td.id] = td

func _parse_buffs(arr: Array) -> void:
	for d in arr:
		if not d is Dictionary or not d.has("id") or d["id"] == "":
			push_warning("ModBundle: skipping buff def with missing id")
			continue
		var bd = BuffDefScript.new()
		bd.parse(d)
		buff_defs[bd.id] = bd
