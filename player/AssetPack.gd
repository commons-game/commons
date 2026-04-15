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
## Mods declare buff→body_id mappings via register_buff_body_map() so Player
## can resolve the correct body variant without a hard dependency on each mod.
##
## Usage:
##   var tex := AssetPack.resolve("body", "necromancer")   # finds necromancer pack
##   var body := AssetPack.resolve_body_for_buffs(["blood_harvest"])  # "necromancer"
class_name AssetPack

## Active pack name. "debug" = colored placeholder sprites; "default" = real art.
static var current_pack: String = "debug"

## Extra packs registered by mods: pack_name -> { slot -> { variant -> path } }
static var _registered: Dictionary = {}

## buff_id -> body_variant, registered by mods.
static var _buff_body_map: Dictionary = {}

## Register a custom asset pack (called by mod packs at load time).
static func register_pack(pack_name: String, mappings: Dictionary) -> void:
	_registered[pack_name] = mappings

## Register buff_id → body_variant mappings (called by mod packs at load time).
## When multiple buffs map to different bodies, the first match wins.
static func register_buff_body_map(mappings: Dictionary) -> void:
	for k in mappings:
		_buff_body_map[k] = str(mappings[k])

## Given a list of active buff IDs, return the body_variant to render.
## Returns "default" if no buff has a registered body override.
static func resolve_body_for_buffs(buff_ids: Array) -> String:
	for buff_id in buff_ids:
		if _buff_body_map.has(buff_id):
			return _buff_body_map[buff_id]
	return "default"

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
