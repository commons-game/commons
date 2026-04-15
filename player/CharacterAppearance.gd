## CharacterAppearance — visual state snapshot for a player character.
## Synced across network (appearance IDs only, not textures).
## Resolved to actual visual layers by CharacterRenderer + AssetPack on each client.
class_name CharacterAppearance

## Base body variant. "default" = plain human silhouette.
## Mod packs can register new body IDs (e.g. "necromancer" for robes).
var body_id: String = "default"

## What the player is currently holding. "" = empty hand.
## Possible values: "lantern", "shovel", "bone_wand"
var held_item_id: String = ""

## Active buff IDs driving visual overlays (e.g. "blood_harvest", "undead_resilience").
## Populated by BuffManager; CharacterRenderer maps these to texture overlays.
var active_buff_ids: Array[String] = []

## Current facing direction — synced so all clients render the same direction.
var facing: Vector2 = Vector2.UP

## Walk animation frame index (0=neutral, 1=left-foot-forward, 2=right-foot-forward).
## Driven locally by movement; not synced (cosmetic only).
var walk_frame: int = 0

## Map facing vector to sprite sheet row (standard RPG layout).
## Row 0=DOWN, 1=LEFT, 2=RIGHT, 3=UP.
func facing_to_row() -> int:
	# Pick dominant axis, then quadrant
	if abs(facing.y) >= abs(facing.x):
		return 0 if facing.y > 0 else 3  # DOWN or UP
	else:
		return 1 if facing.x < 0 else 2  # LEFT or RIGHT

func to_dict() -> Dictionary:
	return {
		"body_id": body_id,
		"held_item_id": held_item_id,
		"active_buff_ids": active_buff_ids.duplicate(),
		"facing_x": facing.x,
		"facing_y": facing.y,
	}

func from_dict(d: Dictionary) -> void:
	body_id = str(d.get("body_id", "default"))
	held_item_id = str(d.get("held_item_id", ""))
	var raw: Array = d.get("active_buff_ids", [])
	active_buff_ids.clear()
	for b in raw:
		active_buff_ids.append(str(b))
	facing = Vector2(float(d.get("facing_x", 0.0)), float(d.get("facing_y", -1.0)))
