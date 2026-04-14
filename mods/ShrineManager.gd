## ShrineManager — runtime coordinator for shrine territory and player buffs.
##
## Sits as a child of World. Player calls on_player_position() each physics tick.
## Emits buffs_changed when the active buff list changes.
##
## Also handles shrine placement: place_shrine(world_tile_pos, bundle_json, owner_id).
extends Node

const ShrineTerritoryScript := preload("res://mods/ShrineTerritory.gd")
const ShrineObjectScript    := preload("res://mods/ShrineObject.gd")
const BuffManagerScript     := preload("res://mods/BuffManager.gd")
const ModBundleScript       := preload("res://mods/ModBundle.gd")

## Emitted when the player's active buff list changes (enter/leave shrine territory).
signal buffs_changed(buffs: Array)
## Emitted when a shrine is placed — carries shrine_id and chunk coords.
signal shrine_placed(shrine_id: String, chunk: Vector2i)

var territory: ShrineTerritoryScript
var buff_manager: BuffManagerScript

var _shrines: Dictionary = {}  # shrine_id -> ShrineObject
var _bundles: Dictionary = {}  # shrine_id -> ModBundle
var _last_chunk: Vector2i = Vector2i(-9999, -9999)

func _ready() -> void:
	territory    = ShrineTerritoryScript.new()
	buff_manager = BuffManagerScript.new()
	buff_manager.territory = territory

## Place a shrine at the chunk containing world_tile_pos.
## bundle_json is a JSON string describing the mod (see template in ModEditor).
## Returns the shrine_id on success, empty string on failure.
func place_shrine(world_tile_pos: Vector2i, bundle_json: String, owner_id: String) -> String:
	var chunk := CoordUtils.world_to_chunk(world_tile_pos)
	var shrine_id := "shrine_%d_%d" % [chunk.x, chunk.y]

	# Replace existing shrine at same location
	if _shrines.has(shrine_id):
		(_shrines[shrine_id] as Object).remove(territory)
		_shrines.erase(shrine_id)
		_bundles.erase(shrine_id)

	var bundle: ModBundleScript = ModBundleScript.new()
	bundle.load_from_json(bundle_json)

	var shrine: ShrineObjectScript = ShrineObjectScript.new()
	shrine.owner_id         = owner_id
	shrine.mod_bundle_hash  = shrine_id
	shrine.initialize(shrine_id, chunk, territory)

	_shrines[shrine_id] = shrine
	_bundles[shrine_id] = bundle

	print("ShrineManager: placed '%s' at chunk %s" % [shrine_id, chunk])
	shrine_placed.emit(shrine_id, chunk)

	# Re-evaluate buffs in case player is already inside this territory
	_evaluate_chunk(_last_chunk)
	return shrine_id

## Called by Player every physics tick.
func on_player_position(world_tile_pos: Vector2i) -> void:
	var new_chunk := CoordUtils.world_to_chunk(world_tile_pos)
	if new_chunk == _last_chunk:
		return
	_last_chunk = new_chunk
	# Notify territory of any modification (expands territory on edit — player movement
	# alone doesn't count as modification, but the territory may already be registered).
	_evaluate_chunk(new_chunk)

## Returns the active shrine id for the player's current position, or "" if wilderness.
func get_active_shrine(world_tile_pos: Vector2i) -> String:
	var chunk := CoordUtils.world_to_chunk(world_tile_pos)
	var active = territory.get_active_mod_set(chunk)
	return active if active != null else ""

## Returns a copy of the current active buff list.
func get_buffs() -> Array:
	return buff_manager.get_buffs()

# --- Internal ---

func _evaluate_chunk(new_chunk: Vector2i) -> void:
	var prev_buffs: Array = buff_manager.get_buffs()

	# Evict buffs that no longer belong to this chunk's shrine
	buff_manager.on_chunk_changed(new_chunk)

	# Grant entry buffs from the active shrine (if any)
	var _active_mod = territory.get_active_mod_set(new_chunk)
	var active_shrine: String = str(_active_mod) if _active_mod != null else ""
	if active_shrine != "" and _bundles.has(active_shrine):
		var bundle: ModBundleScript = _bundles[active_shrine] as ModBundleScript
		var current_buffs: Array = buff_manager.get_buffs()
		for buff_id in bundle.buff_defs:
			var already_has := false
			for b in current_buffs:
				if b["buff_id"] == buff_id:
					already_has = true
					break
			if not already_has:
				buff_manager.add_buff(buff_id, active_shrine)

	var new_buffs: Array = buff_manager.get_buffs()
	# Emit only when the list actually changed
	if new_buffs.size() != prev_buffs.size():
		buffs_changed.emit(new_buffs)
