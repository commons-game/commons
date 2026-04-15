## AssetPack — resolves visual slot + variant to a texture.
##
## Two built-in packs:
##   "debug"   — returns textures from res://assets/debug/<slot>/<variant>.png
##   "default" — returns textures from res://assets/default/<slot>/<variant>.png
## Both paths use the same convention; "debug" assets are colored placeholder sprites.
##
## Mods register additional packs via register_pack(). Registered pack assets
## are always reachable regardless of current_pack — so resolve("body","necromancer")
## finds the necromancer pack even when current_pack is "debug".
##
## Mods declare buff→slot mappings via register_buff_slot_map() so Player
## can resolve the correct variant without a hard dependency on each mod.
## Convenience wrappers register_buff_body_map() and register_buff_item_map() are
## kept for backwards compatibility.
##
## Usage:
##   var tex := AssetPack.resolve("body", "necromancer")
##   var body := AssetPack.resolve_slot_for_buffs("body", ["blood_harvest"])
##   var body := AssetPack.resolve_body_for_buffs(["blood_harvest"])  # legacy wrapper
class_name AssetPack

## Active pack name. "debug" = colored placeholder sprites; "default" = real art.
static var current_pack: String = "debug"

## Extra packs registered by mods: pack_name -> { slot -> { variant -> path } }
static var _registered: Dictionary = {}

## Unified buff slot maps: slot -> { buff_id -> variant }.
## Replaces the old _buff_body_map / _buff_item_map.
static var _buff_slot_maps: Dictionary = {}

## Legacy aliases kept for backward compatibility with existing code + tests.
## These are thin views into _buff_slot_maps["body"] and _buff_slot_maps["held_item"].
static var _buff_body_map: Dictionary:
	get:
		if _buff_slot_maps.has("body"):
			return _buff_slot_maps["body"] as Dictionary
		return {}
	set(value):
		_buff_slot_maps["body"] = value

static var _buff_item_map: Dictionary:
	get:
		if _buff_slot_maps.has("held_item"):
			return _buff_slot_maps["held_item"] as Dictionary
		return {}
	set(value):
		_buff_slot_maps["held_item"] = value

## Register a custom asset pack (called by mod packs at load time).
static func register_pack(pack_name: String, mappings: Dictionary) -> void:
	_registered[pack_name] = mappings

## Register buff_id → variant mappings for a given slot.
## When multiple buffs map to different variants, the first match wins.
static func register_buff_slot_map(slot: String, map: Dictionary) -> void:
	if not _buff_slot_maps.has(slot):
		_buff_slot_maps[slot] = {}
	for k in map:
		(_buff_slot_maps[slot] as Dictionary)[k] = str(map[k])

## Legacy wrapper: register buff_id → body_variant mappings.
static func register_buff_body_map(mappings: Dictionary) -> void:
	register_buff_slot_map("body", mappings)

## Legacy wrapper: register buff_id → held_item_id mappings.
static func register_buff_item_map(mappings: Dictionary) -> void:
	register_buff_slot_map("held_item", mappings)

## Given a slot name and active buff IDs, return the variant to render.
## Returns "default" for "body", "" for all other slots, if no match found.
static func resolve_slot_for_buffs(slot: String, buff_ids: Array) -> String:
	if _buff_slot_maps.has(slot):
		var slot_map: Dictionary = _buff_slot_maps[slot] as Dictionary
		for buff_id in buff_ids:
			if slot_map.has(buff_id):
				return str(slot_map[buff_id])
	# Default fallback depends on slot
	return "default" if slot == "body" else ""

## Legacy wrapper: resolve body variant from buff list.
## Returns "default" if no buff has a registered body override.
static func resolve_body_for_buffs(buff_ids: Array) -> String:
	return resolve_slot_for_buffs("body", buff_ids)

## Legacy wrapper: resolve held_item_id from buff list.
## Returns "" (no override) if no buff has a registered item.
static func resolve_item_for_buffs(buff_ids: Array) -> String:
	return resolve_slot_for_buffs("held_item", buff_ids)

## Resolve slot+variant to a Texture2D.
## Search order: registered packs first (any pack), then built-in packs.
## Returns null if no texture found (CharacterRenderer falls back to draw-code).
static func resolve(slot: String, variant: String) -> Texture2D:
	# Search ALL registered packs — mod assets are always accessible regardless of current_pack.
	for pack_name in _registered:
		var pack: Dictionary = _registered[pack_name]
		if pack.has(slot) and (pack[slot] as Dictionary).has(variant):
			var path: String = (pack[slot] as Dictionary)[variant]
			if ResourceLoader.exists(path):
				return load(path) as Texture2D

	# Built-in packs: current_pack sets the art style (debug placeholder vs real art).
	if current_pack == "debug" or current_pack == "default":
		var path := "res://assets/%s/%s/%s.png" % [current_pack, slot, variant]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D

	return null
