## NecromancerPack — registers the Necromancer mod's asset pack and bundle.
##
## Added as a child of World on startup. Calls AssetPack.register_pack() so
## CharacterRenderer can resolve necromancer body and held-item textures.
##
## Visual mappings:
##   body slot     "necromancer"  → res://assets/necromancer/body/necromancer.png
##   held_item slot "bone_wand"  → res://assets/necromancer/held_item/bone_wand.png
##
## Buff → body_id mapping (used by Player._on_buffs_changed):
##   "blood_harvest"    → body_id = "necromancer"
##   "undead_resilience" → body_id = "necromancer"  (same robes)
##
## This is Phase-0 built-in registration. Phase 2+: mods self-register via
## a mod loader that reads the bundle JSON and an accompanying pack manifest.
extends Node

const AssetPackScript := preload("res://player/AssetPack.gd")

## Maps buff_id -> body_id override. Checked by Player when buffs change.
const BUFF_BODY_MAP: Dictionary = {
	"blood_harvest":     "necromancer",
	"undead_resilience": "necromancer",
}
## Maps buff_id -> held_item_id. Shrine grants the wand visually on entry.
const BUFF_ITEM_MAP: Dictionary = {
	"blood_harvest": "bone_wand",
}

func _ready() -> void:
	AssetPackScript.register_pack("necromancer", {
		"body": {
			"necromancer": "res://assets/necromancer/body/necromancer.png",
		},
		"held_item": {
			"bone_wand": "res://assets/necromancer/held_item/bone_wand.png",
		},
	})
	AssetPackScript.register_buff_body_map(BUFF_BODY_MAP)
	AssetPackScript.register_buff_item_map(BUFF_ITEM_MAP)
