## CharacterRenderer — compositable character visual layer manager.
##
## Named slots rendered bottom-to-top (z_index order):
##   shadow (z=-1), body (z=0), feet (z=0), held_item (z=1),
##   armor (z=1), head (z=2), status_effect (z=3)
##
## The "body" slot uses a sprite sheet (48x96, 3 frames × 4 directions).
## Region rect is updated each refresh() based on facing row and walk_frame.
##
## When any sprite is visible, the parent's _draw() fallback (white circle) is
## suppressed by CharacterRenderer calling queue_redraw() and Parent._draw()
## checking has_visible_sprites() before drawing.
##
## Attach as a child of Player or RemotePlayer. Call refresh(appearance) when
## CharacterAppearance changes.
class_name CharacterRenderer
extends Node2D

## Preload to avoid class_name resolution ordering issues.
const AssetPackScript := preload("res://player/AssetPack.gd")

## Sprite sheet frame dimensions (pixels).
const FRAME_W := 16
const FRAME_H := 24

## Slot names in draw order (back to front).
const SLOTS := ["shadow", "body", "feet", "held_item", "armor", "head", "status_effect"]

## Sprite2D node per slot.
var _sprites: Dictionary = {}  # slot_name -> Sprite2D

## Last appearance dict we rendered — skip refresh if nothing changed.
var _last_appearance: Dictionary = {}

func _ready() -> void:
	for i in range(SLOTS.size()):
		var slot: String = SLOTS[i]
		var spr := Sprite2D.new()
		spr.name = "Slot_%s" % slot
		spr.z_index = i - 1  # shadow=-1, body=0, ... status_effect=5
		spr.visible = false
		add_child(spr)
		_sprites[slot] = spr

## Returns true if at least one slot sprite is currently visible.
## Used by Player._draw() to suppress the draw-code fallback.
func has_visible_sprites() -> bool:
	for slot in _sprites:
		if (_sprites[slot] as Sprite2D).visible:
			return true
	return false

## Update visual state from a CharacterAppearance.
## Bails early if nothing changed since last call.
## Parameter typed as Object to avoid class_name resolution ordering issues.
func refresh(appearance: Object) -> void:
	var d: Dictionary = appearance.call("to_dict")
	var row: int = appearance.call("facing_to_row")
	var frame: int = int(appearance.get("walk_frame"))

	# Rebuild key that includes animation state (not in to_dict since walk_frame
	# is cosmetic-only and not network-synced).
	var anim_key := "%s|%d|%d" % [str(d), row, frame]
	if anim_key == _last_appearance.get("_anim_key", ""):
		return
	_last_appearance["_anim_key"] = anim_key

	_apply_body_slot(str(d.get("base_body_id", "default")), row, frame)

	var held: String = str(d.get("held_item_id", ""))
	_apply_slot("held_item", held if held != "" else "__none__")

	var buffs: Array = d.get("active_buff_ids", [])
	var status_variant: String = str(buffs[0]) if not buffs.is_empty() else "__none__"
	_apply_slot("status_effect", status_variant)

	# Equipment slots — driven by appearance IDs set by Player from EquipmentInventory.
	var armor_id: String = str(d.get("armor_id", ""))
	_apply_slot("armor", armor_id if armor_id != "" else "__none__")

	var head_id: String = str(d.get("head_id", ""))
	_apply_slot("head", head_id if head_id != "" else "__none__")

	var feet_id: String = str(d.get("feet_id", ""))
	_apply_slot("feet", feet_id if feet_id != "" else "__none__")

	for slot: String in ["shadow"]:
		(_sprites[slot] as Sprite2D).visible = false

	# Notify parent to re-evaluate whether draw-code fallback is needed.
	get_parent().queue_redraw()

## Apply the body slot with sprite sheet region rect.
func _apply_body_slot(variant: String, row: int, frame: int) -> void:
	var spr := _sprites["body"] as Sprite2D
	var tex: Texture2D = AssetPackScript.resolve("body", variant)
	if tex == null:
		spr.visible = false
		return
	spr.texture = tex
	spr.region_enabled = true
	spr.region_rect = Rect2(frame * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)
	# Center the sprite on the node origin (Sprite2D default is centered).
	spr.centered = true
	spr.offset = Vector2(0, FRAME_H * 0.5 - FRAME_H * 0.5)  # no offset needed when centered
	spr.visible = true

## Resolve + apply one slot (non-animated). Hides if no texture.
func _apply_slot(slot: String, variant: String) -> void:
	var spr := _sprites[slot] as Sprite2D
	if variant == "__none__":
		spr.visible = false
		return
	var tex: Texture2D = AssetPackScript.resolve(slot, variant)
	if tex == null:
		spr.visible = false
	else:
		spr.texture = tex
		spr.visible = true
