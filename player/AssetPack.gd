## AssetPack — resolves visual slot + variant to a texture.
##
## Two built-in packs:
##   "debug"   — returns textures from res://assets/debug/<slot>/<variant>.png
##   "default" — returns textures from res://assets/default/<slot>/<variant>.png
## Both paths use the same convention; "debug" assets are colored placeholder sprites.
##
## Mods can register additional packs at runtime via register_pack().
##
## Usage:
##   var tex := AssetPack.resolve("body", "necromancer")
##   if tex: sprite.texture = tex
class_name AssetPack

## Active pack name. "debug" = colored placeholder sprites; "default" = real art.
static var current_pack: String = "debug"

## Extra packs registered by mods: pack_name -> { slot -> { variant -> path } }
static var _registered: Dictionary = {}

## Register a custom asset pack (called by mod bundles at load time).
static func register_pack(pack_name: String, mappings: Dictionary) -> void:
	_registered[pack_name] = mappings

## Resolve slot+variant for the active pack. Returns null if no texture found
## (CharacterRenderer should fall back to draw-code when null is returned).
static func resolve(slot: String, variant: String) -> Texture2D:
	# Check registered packs first
	if _registered.has(current_pack):
		var pack: Dictionary = _registered[current_pack]
		if pack.has(slot) and (pack[slot] as Dictionary).has(variant):
			var path: String = (pack[slot] as Dictionary)[variant]
			if ResourceLoader.exists(path):
				return load(path) as Texture2D
			return null

	# Built-in packs: same path convention, different root dir
	if current_pack == "debug" or current_pack == "default":
		var path := "res://assets/%s/%s/%s.png" % [current_pack, slot, variant]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
		return null

	return null
