## AlchemistPack — registers the Alchemist mod's asset pack and buff mappings.
##
## Visual mappings:
##   body slot      "alchemist" → res://assets/alchemist/body/alchemist.png
##   held_item slot "potion"    → res://assets/alchemist/held_item/potion.png
##
## Buff → visual mappings:
##   "swift_brew"        → body=alchemist, item=potion
##   "alchemical_focus"  → body=alchemist, item=potion
extends Node

const AssetPackScript := preload("res://player/AssetPack.gd")

const BUFF_BODY_MAP: Dictionary = {
	"swift_brew":       "alchemist",
	"alchemical_focus": "alchemist",
}

const BUFF_ITEM_MAP: Dictionary = {
	"swift_brew": "potion",
}

func _ready() -> void:
	AssetPackScript.register_pack("alchemist", {
		"body": {
			"alchemist": "res://assets/alchemist/body/alchemist.png",
		},
		"held_item": {
			"potion": "res://assets/alchemist/held_item/potion.png",
		},
	})
	AssetPackScript.register_buff_body_map(BUFF_BODY_MAP)
	AssetPackScript.register_buff_item_map(BUFF_ITEM_MAP)
