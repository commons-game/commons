## Player — top-down WASD movement. Notifies ChunkManager of position each tick.
extends CharacterBody2D

const SPEED := 80.0

var hp: int = 100
var max_hp: int = 100
var _dead: bool = false

## Hunger stats.
var food: int = 100
var max_food: int = 100
var _food_timer: float = 0.0
const FOOD_DRAIN_INTERVAL := 8.0   # deplete 1 food every 8 seconds
var _starvation_timer: float = 0.0
const STARVATION_INTERVAL := 4.0   # take 2 damage every 4 seconds when food=0
const STARVATION_DAMAGE := 2

const ATTACK_DAMAGE := 25
const ATTACK_RANGE := 1.5  # tiles

## Campfire healing — passive regen when near a campfire and out of combat.
var _combat_cooldown: float = 0.0     # seconds since last damage taken
const COMBAT_COOLDOWN_S := 5.0        # must be clear of combat this long to regen
var _campfire_heal_timer: float = 0.0 # ticks up toward CAMPFIRE_HEAL_INTERVAL
const CAMPFIRE_HEAL_INTERVAL := 3.0   # heal 1 HP every 3 seconds near fire
const CAMPFIRE_HEAL_RANGE   := 6      # tiles — matches CampfireRegistry light radius

## Visual flash timers for combat feedback.
var _damage_flash_timer: float = 0.0
const DAMAGE_FLASH_DURATION := 0.15
var _pickup_flash_timer: float = 0.0
const PICKUP_FLASH_DURATION := 0.2
var _attack_arc_timer: float = 0.0
const ATTACK_ARC_DURATION := 0.12

## Filled circle radius and direction-triangle half-width (in pixels).
const RADIUS := 7.0
const TRI_SIZE := 4.0

## Track last non-zero velocity for the direction indicator.
var _facing := Vector2.UP
var _attack_cooldown: float = 0.0
## Set by World._setup_merge_system() after both Player and MergeCoordinator are ready.
var coordinator: Node = null
var _last_chunk: Vector2i = Vector2i(-9999, -9999)

## Walk animation: accumulates distance moved to drive frame changes.
var _walk_dist: float = 0.0
## Distance per walk frame step (pixels). At SPEED=80 this cycles ~every 0.15s.
const WALK_STEP := 12.0

const ShrineManagerScript          := preload("res://mods/ShrineManager.gd")
const LanternScript                := preload("res://player/Lantern.gd")
const CharacterAppearanceScript    := preload("res://player/CharacterAppearance.gd")
const CharacterRendererScript      := preload("res://player/CharacterRenderer.gd")
const AssetPackScript              := preload("res://player/AssetPack.gd")
const InventoryScript              := preload("res://items/Inventory.gd")
const EquipmentInventoryScript     := preload("res://items/EquipmentInventory.gd")
# Structure scenes are no longer preloaded here — they're instantiated by
# ChunkManager via StructureRegistry after their CRDT tiles are placed.

## Atlas coords for harvestable tiles (layer 1 object layer).
## Tree: atlas (0, 1) on grass ground.
## Rock: atlas (1, 1) on stone ground.
## Ground atlas: grass=0, dirt=1, stone=2, water=3.
const ATLAS_TREE  := Vector2i(0, 1)
const ATLAS_ROCK  := Vector2i(1, 1)

## Home position for respawn (set by placing a bedroll).
var home_pos: Vector2 = Vector2.ZERO
var _has_home: bool = false
## Local record of which tile holds our Tether, for spawn-anchor bookkeeping.
## Ownership isn't stored on the Tether tile itself — each player tracks their
## own home tile here. Cleared when that tile is removed (tile_remove event).
var _home_tile_pos: Vector2i = Vector2i(-2147483647, -2147483647)

## Placed structure nodes (campfires/bedrolls) owned by this player.

@onready var chunk_manager: ChunkManager    = $"../ChunkManager"
@onready var shrine_manager: ShrineManagerScript = $"../ShrineManager"
@onready var _camera: Camera2D = $Camera2D

var inventory: Object = null   # Inventory — set up in _ready
var equipment: Object = null   # EquipmentInventory — set up in _ready
var _lantern: Node = null
var appearance = null  # CharacterAppearance
var _renderer  = null  # CharacterRenderer

func _ready() -> void:
	# Always render above all tile layers (GroundLayer=0, ObjectLayer=1).
	z_index = 2
	appearance = CharacterAppearanceScript.new()
	_renderer = CharacterRendererScript.new()
	_renderer.name = "CharacterRenderer"
	add_child(_renderer)

	inventory = InventoryScript.new()
	# Starter loadout: lantern in slot 0, shovel in slot 1.
	inventory.set_tool_slot(0, {"id": "lantern", "category": "tool", "count": 1})
	inventory.set_tool_slot(1, {"id": "shovel",  "category": "tool", "count": 1})

	equipment = EquipmentInventoryScript.new()
	var eq_data: Dictionary = Backend.load_equipment()
	if not eq_data.is_empty():
		equipment.from_dict(eq_data)

	_lantern = LanternScript.new()
	_lantern.name = "Lantern"
	add_child(_lantern)

	# Connect ChatSystem for speech bubble spawning
	if Engine.get_main_loop() != null:
		ChatSystem.message_received.connect(_on_chat_message)

	# Listen for tile removals so we notice when our Tether is broken by
	# anyone (local or remote peer). Connects deferred because the bus may
	# not be in the scene tree yet during Player._ready.
	call_deferred("_connect_tile_bus")

func _connect_tile_bus() -> void:
	var bus: Node = get_node_or_null("../TileMutationBus")
	if bus == null:
		return
	if not bus.is_connected("tile_removed", _on_tile_removed):
		bus.tile_removed.connect(_on_tile_removed)

## Reacts to any tile removal in the world. We only care about our own home
## tile — if the Tether we rely on was destroyed, clear the anchor and show
## the life-event message.
func _on_tile_removed(world_coords: Vector2i, layer: int) -> void:
	if layer != 1 or not _has_home or world_coords != _home_tile_pos:
		return
	_has_home = false
	home_pos = Vector2.ZERO
	_home_tile_pos = Vector2i(-2147483647, -2147483647)
	print("Player: Tether broken — home anchor lost.")
	_show_tether_broken_message()

func _draw() -> void:
	var has_sprites: bool = _renderer != null and _renderer.has_visible_sprites()
	if has_sprites:
		# With sprites: apply modulate tint for flash feedback.
		if _damage_flash_timer > 0.0:
			modulate = Color(1.0, 0.3, 0.3)
		elif _pickup_flash_timer > 0.0:
			modulate = Color(0.3, 1.0, 0.3)
		else:
			modulate = Color.WHITE
	else:
		# Reset modulate so fallback circle colors are unaffected.
		modulate = Color.WHITE
		# Determine circle fill color based on active flash.
		var fill_color: Color
		if _damage_flash_timer > 0.0:
			fill_color = Color(1.0, 0.2, 0.2)
		elif _pickup_flash_timer > 0.0:
			fill_color = Color(0.3, 1.0, 0.3)
		else:
			fill_color = Color.WHITE
		# Fallback: filled circle with dark outline + direction triangle.
		draw_circle(Vector2.ZERO, RADIUS, Color(0.15, 0.15, 0.15))   # shadow/outline
		draw_circle(Vector2.ZERO, RADIUS - 1.0, fill_color)
		# Direction triangle: small filled triangle pointing in _facing direction
		var tip   := _facing * (RADIUS + TRI_SIZE)
		var left  := _facing.rotated(deg_to_rad( 140.0)) * (TRI_SIZE * 0.8)
		var right := _facing.rotated(deg_to_rad(-140.0)) * (TRI_SIZE * 0.8)
		draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.9, 0.7, 0.1))
	# Attack arc: drawn on top regardless of sprite mode.
	if _attack_arc_timer > 0.0:
		var facing_angle := _facing.angle()
		var alpha := _attack_arc_timer / ATTACK_ARC_DURATION
		draw_arc(Vector2.ZERO, RADIUS + 6.0, facing_angle - 0.6, facing_angle + 0.6, 8, Color(1.0, 0.9, 0.2, alpha), 2.0)

func take_damage(amount: int) -> void:
	if _dead:
		return
	hp = max(0, hp - amount)
	_damage_flash_timer = DAMAGE_FLASH_DURATION
	_combat_cooldown = COMBAT_COOLDOWN_S  # reset out-of-combat window
	print("Player: took %d damage, hp=%d/%d" % [amount, hp, max_hp])
	if hp == 0:
		_on_player_died()
	else:
		_shake_camera(5.0, 0.25)

func _shake_camera(intensity: float, duration: float) -> void:
	if _camera == null:
		return
	var tween := create_tween()
	var steps := 4
	var step_time := duration / steps
	for _i in range(steps):
		var offset := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(_camera, "offset", offset, step_time)
	tween.tween_property(_camera, "offset", Vector2.ZERO, step_time)

## Save a timestamped PNG of the current viewport to user://screenshots/.
## Used by the laptop playtest loop (dev/play.sh) to ship visual state back
## to the dev server.
func _save_screenshot() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("screenshots"):
		dir.make_dir("screenshots")
	var img := get_viewport().get_texture().get_image()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://screenshots/%s.png" % stamp
	img.save_png(path)
	print("[SCREENSHOT] saved %s" % path)
	if is_instance_valid(EventLog):
		EventLog.record("screenshot", {"path": path})

## Returns the id of the item the player is currently wielding. Prefers the
## hotbar's active bag slot (what the user sees highlighted on the bottom bar),
## falls back to the tool_slot at active_tool_index. Empty string if nothing.
##
## Shared by TileInteraction (to route clicks) and _auto_off_lantern_if_not_wielded.
func wielded_item_id() -> String:
	var hotbar := get_parent().get_node_or_null("Hotbar") if get_parent() != null else null
	if hotbar != null:
		var stack: Dictionary = hotbar.call("get_active_stack") as Dictionary
		var id: String = str(stack.get("id", ""))
		if id != "":
			return id
	if inventory != null:
		var active: Dictionary = inventory.get_active_tool()
		return str(active.get("id", ""))
	return ""

## Per-frame guard: lantern stays lit only while the player is actively
## wielding it. Switching to a different hotbar slot or dragging the lantern
## anywhere the wielded-item lookup no longer returns "lantern" extinguishes it.
func _auto_off_lantern_if_dropped() -> void:
	if _lantern == null or not _lantern.is_on:
		return
	if wielded_item_id() == "lantern":
		return
	_lantern.set_on(false)

func _on_player_died() -> void:
	_dead = true
	print("Player: died — starting respawn sequence")
	if is_instance_valid(EventLog):
		EventLog.record("player_died", {"pos": position})

	# Drop all inventory items as loot tiles at the death position before fading out.
	_drop_inventory_as_loot()

	# Build full-screen black overlay.
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 99
	add_child(overlay_layer)
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.size = Vector2(1280, 720)
	overlay_layer.add_child(overlay)

	# Fade to black.
	var tween := create_tween()
	tween.tween_property(overlay, "color", Color(0, 0, 0, 1), 0.6)
	await tween.finished

	# Show "YOU DIED" text at full black.
	var died_label := Label.new()
	died_label.text = "YOU DIED"
	died_label.add_theme_font_size_override("font_size", 48)
	died_label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
	died_label.position = Vector2(1280 / 2 - 120, 720 / 2 - 30)
	overlay_layer.add_child(died_label)

	# Wait a moment at full black.
	await get_tree().create_timer(0.4).timeout

	# Reset player state.
	hp = max_hp
	food = max_food
	position = home_pos if _has_home else Vector2.ZERO

	# Fair-start promise: fresh spawns (no Tether) wake at dawn.
	# Tethered players respawn at current time — the Tether trades fair timing for a fixed home.
	# See docs/game_design.md § "Spawn timing".
	var advanced_to_dawn: bool = false
	if not _has_home and not DayClock.is_daytime():
		DayClock.advance_to_phase(0.02)  # just past dawn so the world reads as "morning"
		advanced_to_dawn = true
		print("Player: fresh spawn mid-night — clock advanced to dawn")
	if is_instance_valid(EventLog):
		EventLog.record("player_respawned", {
			"pos": position, "has_home": _has_home, "advanced_to_dawn": advanced_to_dawn,
		})

	# Fade back in.
	_dead = false
	var tween2 := create_tween()
	tween2.tween_property(overlay, "color", Color(0, 0, 0, 0), 0.6)
	await tween2.finished

	overlay_layer.queue_free()

## Drop all bag contents as loot_pickup tiles at the player's current tile.
## Tool slots are kept (lantern, shovel are not lost on death — too punishing).
## Clears the bag after dropping.
func _drop_inventory_as_loot() -> void:
	if inventory == null or chunk_manager == null:
		return
	var drop_tile := Vector2i(int(floorf(position.x / Constants.TILE_SIZE)),
	                          int(floorf(position.y / Constants.TILE_SIZE)))
	var dropped := 0
	for i in range(inventory.BAG_SIZE):
		var slot: Dictionary = inventory.bag[i] as Dictionary
		if slot.is_empty():
			continue
		# Scatter each stack to a nearby tile (offset so they don't all stack on one).
		var offset_x := dropped % 3 - 1   # -1, 0, 1
		var offset_y := dropped / 3 - 1
		var tile_pos := drop_tile + Vector2i(offset_x, offset_y)
		chunk_manager.place_tile(tile_pos, 1, 0, Vector2i(3, 1), 0, "loot_pickup")
		dropped += 1
	if dropped > 0:
		print("Player: dropped %d bag slots as loot on death" % dropped)
	# Clear bag (tool slots kept — they're equipped, not carried).
	for i in range(inventory.BAG_SIZE):
		inventory.bag[i] = {}

## Attempt to start an attack swing. Sets cooldown and triggers the arc visual.
## Returns true if the swing was initiated (cooldown was ready), false if still
## on cooldown. Call this from TileInteraction for tile hits to share cooldown.
func start_swing() -> bool:
	if _attack_cooldown > 0.0:
		return false
	_attack_cooldown = 0.5
	_attack_arc_timer = ATTACK_ARC_DURATION
	return true

func _do_attack() -> void:
	if not start_swing():
		return
	var tile_pos := Vector2i(int(floorf(position.x / Constants.TILE_SIZE)),
	                         int(floorf(position.y / Constants.TILE_SIZE)))
	var active_tool: Dictionary = inventory.get_active_tool() if inventory != null else {}
	var tool_id: String = str(active_tool.get("id", "")) if not active_tool.is_empty() else ""
	# Check for mobs first.
	var hit_mob: bool = false
	for node in get_parent().get_children():
		if not node.get_script():
			continue
		if not "mob_died" in node:
			continue
		var mob_tile := Vector2i(int(floorf(node.position.x / Constants.TILE_SIZE)),
		                         int(floorf(node.position.y / Constants.TILE_SIZE)))
		var dist: float = (mob_tile - tile_pos).length()
		if dist <= ATTACK_RANGE:
			var health = node.get_node_or_null("Health")
			if health != null:
				# Tag the mob with the weapon so its death can trigger the reveal effect.
				node.set("last_damage_source", tool_id)
				health.call("take_damage", ATTACK_DAMAGE)
				hit_mob = true
	if hit_mob:
		return
	# Check for Tether nodes in range (enemy or own — either can be attacked).
	for node in get_parent().get_children():
		if node == self:
			continue  # never attack ourselves
		if not node.get_script():
			continue
		if not node.has_method("take_damage"):
			continue
		if not node is Node2D:
			continue
		var node2d := node as Node2D
		var tether_tile := Vector2i(int(floorf(node2d.position.x / Constants.TILE_SIZE)),
		                            int(floorf(node2d.position.y / Constants.TILE_SIZE)))
		var dist: float = (tether_tile - tile_pos).length()
		if dist <= ATTACK_RANGE:
			node.call("take_damage", ATTACK_DAMAGE, tool_id)
			return
	# If no mob or Tether hit, try harvesting the tile in the facing direction.
	var facing_tile := tile_pos + Vector2i(int(round(_facing.x)), int(round(_facing.y)))
	# Clamp to 1 tile max and require clear line of sight.
	if _tile_dist(tile_pos, facing_tile) <= 1.5 and _has_los(tile_pos, facing_tile):
		if _do_harvest(facing_tile):
			# Snap facing toward the harvested tile.
			_facing = Vector2(facing_tile - tile_pos).normalized()

## Returns Chebyshev distance between two tile positions.
func _tile_dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(b - a).length()

## Simple line-of-sight check between two adjacent tiles.
## Returns false if any solid object tile sits between them.
func _has_los(from_tile: Vector2i, to_tile: Vector2i) -> bool:
	if chunk_manager == null:
		return true
	# For adjacent tiles (max distance 1.5) just check the target itself —
	# a tile can't be blocked by something between two adjacent cells.
	# For future longer ranges this would step along the ray.
	return true  # adjacent-only harvest makes LOS trivial for now

## Harvest the harvestable tile at world-tile position tile_pos.
## Returns true if something was harvested.
## Tree  (atlas 0,1) → requires flint_knife → 2 Wood
## Rock  (atlas 1,1) → requires flint_knife → 2 Stone
func _do_harvest(tile_pos: Vector2i) -> bool:
	if chunk_manager == null:
		return false
	# Check object layer first (trees and rocks are on layer 1).
	var obj_tile: Dictionary = chunk_manager.get_object_tile_at(tile_pos)
	var obj_atlas := Vector2i(
		int(obj_tile.get("atlas_x", -1)),
		int(obj_tile.get("atlas_y", -1)))

	var active_tool: Dictionary = inventory.get_active_tool() if inventory != null else {}
	var tool_id: String = str(active_tool.get("id", "")) if not active_tool.is_empty() else ""
	var has_flint: bool = (tool_id == "flint_knife")

	if obj_atlas == ATLAS_TREE:
		if not has_flint:
			_show_harvest_fail("Need flint knife")
			return false
		chunk_manager.remove_tile(tile_pos, 1, "harvest")
		if inventory != null:
			inventory.add_to_bag({"id": "wood", "category": "material", "count": 2}, 20)
			print("Player: harvested tree → 2 Wood")
		return true

	if obj_atlas == ATLAS_ROCK:
		if not has_flint:
			_show_harvest_fail("Need flint knife")
			return false
		chunk_manager.remove_tile(tile_pos, 1, "harvest")
		if inventory != null:
			inventory.add_to_bag({"id": "stone", "category": "material", "count": 2}, 20)
			print("Player: harvested rock → 2 Stone")
		return true

	# Grass is not harvestable — nothing to gather with bare hands yet.
	return false

func _show_harvest_fail(msg: String) -> void:
	# Brief print — subtle feedback without UI popup.
	print("Player: %s" % msg)

## Handle place_use action.
## - If active hotbar slot contains a structure: place it in front of the player.
## - If active hotbar slot is a consumable: use it.
## - Also check for bedrolls in range to activate home-set.
func _do_place_use() -> void:
	# Check for a bedroll in range first (walk onto / activate).
	var tile_pos := Vector2i(int(floorf(position.x / Constants.TILE_SIZE)),
	                         int(floorf(position.y / Constants.TILE_SIZE)))
	var activated: Node = _find_nearby_bedroll(tile_pos, 1.5)
	if activated != null:
		activated.call("activate", position)
		return

	# Check active hotbar slot.
	var hotbar := get_node_or_null("../Hotbar")
	var active_stack: Dictionary = {}
	if hotbar != null:
		active_stack = hotbar.call("get_active_stack") as Dictionary
	else:
		# Fallback: active tool slot
		if inventory != null:
			active_stack = inventory.get_active_tool()

	if active_stack.is_empty():
		return

	var item_id: String = str(active_stack.get("id", ""))
	var item_cat: String = str(active_stack.get("category", ""))

	if item_cat == "structure":
		_place_structure(item_id)
	elif item_cat == "food":
		_try_eat()

## Predicate: is `item_id` a placeable structure?
##
## True iff the id is registered as a tile AND its atlas coord is registered as
## a structure scene. Both registries must agree — having only a TileRegistry
## entry (e.g. "grass") or only a StructureRegistry entry (would be a bug) does
## not qualify. Static so unit tests can call it without instantiating Player.
##
## Replaces a hardcoded whitelist that silently dropped any new structure
## (workbench was the last casualty).
static func is_structure_item(item_id: String) -> bool:
	if not TileRegistry.has_tile(item_id):
		return false
	var entry: Dictionary = TileRegistry.resolve(item_id)
	if entry.is_empty():
		return false
	return StructureRegistry.is_structure(entry["atlas"])

## Place a structure one tile in front of the player.
func _place_structure(item_id: String) -> void:
	var tile_pos := Vector2i(int(floorf(position.x / Constants.TILE_SIZE)),
	                         int(floorf(position.y / Constants.TILE_SIZE)))
	var place_tile_pos := tile_pos + Vector2i(int(round(_facing.x)), int(round(_facing.y)))
	# Snap facing toward the placement tile.
	_facing = Vector2(place_tile_pos - tile_pos).normalized()

	# Don't stack on water or existing object tiles.
	if chunk_manager != null:
		var ground: Vector2i = chunk_manager.get_ground_atlas_at(place_tile_pos)
		if ground.x == 3:  # water
			print("Player: can't place structure on water")
			return
		if chunk_manager.has_tile_at(place_tile_pos, 1):
			print("Player: tile already occupied")
			return

	# Consume from inventory (remove from bag, or from tool slot if it's there).
	var consumed: bool = false
	if inventory != null:
		if inventory.bag_stack_total(item_id) > 0:
			inventory.remove_from_bag(item_id, 1)
			consumed = true
		else:
			# Check tool slots.
			for i in range(inventory.TOOL_SLOT_COUNT):
				var slot: Dictionary = inventory.tool_slots[i] as Dictionary
				if str(slot.get("id", "")) == item_id:
					inventory.clear_tool_slot(i)
					consumed = true
					break
	if not consumed:
		print("Player: no %s in inventory" % item_id)
		return

	# Persisted structures go through TileMutationBus → CRDT → StructureRegistry.
	# Registry-driven: any item that is a tile AND whose atlas is a registered
	# structure dispatches here automatically. No hardcoded whitelist — adding a
	# new structure is one entry in TileRegistry + one in StructureRegistry, and
	# placement Just Works without touching this file.
	if is_structure_item(item_id):
		var bus: Node = get_node_or_null("../TileMutationBus")
		if bus == null:
			print("Player: no TileMutationBus — cannot place structure")
			return
		# One Tether per player: if we had one, remove the old tile first so the
		# new placement replaces rather than coexists. Enforcement is local —
		# other peers may have placed their own Tethers.
		if item_id == "tether" and _has_home:
			if chunk_manager != null and chunk_manager.has_tile_at(_home_tile_pos, 1):
				bus.request_remove_tile(_home_tile_pos, 1)
		bus.request_place_tile(place_tile_pos, 1, item_id)
		if item_id == "tether":
			var tether_world_pos := Vector2(
				place_tile_pos.x * Constants.TILE_SIZE + Constants.TILE_SIZE * 0.5,
				place_tile_pos.y * Constants.TILE_SIZE + Constants.TILE_SIZE * 0.5)
			home_pos = tether_world_pos
			_has_home = true
			_home_tile_pos = place_tile_pos
			print("Player: Tether placed — home anchor set at %s" % place_tile_pos)
		print("Player: placed %s at %s (persisted)" % [item_id, place_tile_pos])
		return

	# Unknown structure id — nothing to do.
	print("Player: no structure handler for %s" % item_id)

## Shrines are ownerless — any shrine breaking anywhere shows the banner to
## anyone nearby via a future proximity check. For now, no per-player react.

## Scan loaded chunks around the player for a Bedroll scene within `range_tiles`.
## Returns the first match or null. Used by _do_place_use so walking onto a
## bedroll activates it.
func _find_nearby_bedroll(from_tile: Vector2i, range_tiles: float) -> Node:
	if chunk_manager == null:
		return null
	for chunk in chunk_manager.get_children():
		if not (chunk is Node2D):
			continue
		for child in chunk.get_children():
			if not child.has_method("activate"):
				continue
			if not "world_tile_pos" in child:
				continue
			var s_tile: Vector2i = child.world_tile_pos
			if Vector2(s_tile - from_tile).length() <= range_tiles:
				return child
	return null

## Display "Your Shrine has been broken." in red at screen center for 3 seconds.
func _show_shrine_broken_message() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 98  # just below death overlay
	add_child(canvas)

	var lbl := Label.new()
	lbl.text = "Your Shrine has been broken."
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.05, 0.05))
	# Position at screen centre (1280x720 nominal).
	lbl.position = Vector2(1280.0 / 2.0 - 250.0, 720.0 / 2.0 - 24.0)
	canvas.add_child(lbl)

	# Fade out over 3 seconds (hold 1.5s opaque, then fade).
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.5)
	tween.tween_callback(canvas.queue_free)

## Display "Your Tether has been broken." in red at screen center for 3 seconds.
func _show_tether_broken_message() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 98  # just below death overlay
	add_child(canvas)

	var lbl := Label.new()
	lbl.text = "Your Tether has been broken."
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.05, 0.05))
	# Position at screen centre (1280x720 nominal).
	lbl.position = Vector2(1280.0 / 2.0 - 260.0, 720.0 / 2.0 - 24.0)
	canvas.add_child(lbl)

	# Fade out over 3 seconds (hold 1.5s opaque, then fade).
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.5)
	tween.tween_callback(canvas.queue_free)

func _process(delta: float) -> void:
	queue_redraw()
	_auto_off_lantern_if_dropped()
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	_damage_flash_timer = maxf(_damage_flash_timer - delta, 0.0)
	_pickup_flash_timer = maxf(_pickup_flash_timer - delta, 0.0)
	_attack_arc_timer   = maxf(_attack_arc_timer   - delta, 0.0)
	# Hunger drain — loop so large delta ticks (e.g. in tests) drain correctly.
	_food_timer += delta
	while _food_timer >= FOOD_DRAIN_INTERVAL:
		_food_timer -= FOOD_DRAIN_INTERVAL
		food = max(0, food - 1)
	# Starvation damage disabled until food items exist in the game.
	# TODO: re-enable when food system is implemented.
	_starvation_timer = 0.0
	# Campfire healing — passive regen when near a campfire and out of combat.
	_combat_cooldown = maxf(_combat_cooldown - delta, 0.0)
	if _combat_cooldown <= 0.0 and hp < max_hp and not _dead:
		var tile_pos := Vector2i(int(floorf(position.x / Constants.TILE_SIZE)),
		                         int(floorf(position.y / Constants.TILE_SIZE)))
		var nearest_cf: Vector2i = CampfireRegistry.nearest_campfire_tile(tile_pos)
		if nearest_cf != Vector2i(-9999, -9999) and \
				(nearest_cf - tile_pos).length() <= CAMPFIRE_HEAL_RANGE:
			_campfire_heal_timer += delta
			if _campfire_heal_timer >= CAMPFIRE_HEAL_INTERVAL:
				_campfire_heal_timer -= CAMPFIRE_HEAL_INTERVAL
				hp = min(hp + 1, max_hp)
				_pickup_flash_timer = 0.05  # tiny green flash as subtle feedback
		else:
			_campfire_heal_timer = 0.0

func _physics_process(_delta: float) -> void:
	if _dead:
		return
	var input := Vector2(Input.get_axis("ui_left", "ui_right"),
	                     Input.get_axis("ui_up", "ui_down"))
	var cs := get_node_or_null("../CraftingSystem")
	if cs != null and cs.get("is_open"):
		input = Vector2.ZERO
	velocity = input.normalized() * SPEED
	if input != Vector2.ZERO:
		_facing = input.normalized()
		_walk_dist += SPEED * get_physics_process_delta_time()
		appearance.walk_frame = int(_walk_dist / WALK_STEP) % 3
	else:
		appearance.walk_frame = 0  # neutral when standing still
	appearance.facing = _facing
	_update_appearance()
	move_and_slide()
	var tile_pos := Vector2i(int(floorf(position.x / Constants.TILE_SIZE)),
	                         int(floorf(position.y / Constants.TILE_SIZE)))
	chunk_manager.update_player_position(tile_pos)
	chunk_manager.update_player_last_visited(tile_pos)
	shrine_manager.on_player_position(tile_pos)
	_check_item_pickup(tile_pos)
	var cur_chunk := CoordUtils.world_to_chunk(tile_pos)
	if cur_chunk != _last_chunk:
		_last_chunk = cur_chunk
		if coordinator != null:
			coordinator.update_my_chunk(cur_chunk)
	# Push our position to our RemotePlayer so the synchronizer can broadcast it.
	# Works for both host (RemotePlayer_1) and clients (RemotePlayer_<id>).
	# No-op in single-player (no multiplayer peer assigned, no RemotePlayer exists).
	if multiplayer.has_multiplayer_peer():
		var own_id := multiplayer.get_unique_id()
		var remote := get_node_or_null("../RemotePlayer_%d" % own_id)
		if remote:
			remote.position = global_position
			remote.set("appearance_base_body_id", appearance.base_body_id)
			remote.set("appearance_held_item_id",  appearance.held_item_id)
			remote.set("appearance_facing_x",      appearance.facing.x)
			remote.set("appearance_facing_y",      appearance.facing.y)
			remote.set("appearance_walk_frame",    appearance.walk_frame)
			remote.set("appearance_armor_id",      appearance.armor_id)
			remote.set("appearance_head_id",       appearance.head_id)
			remote.set("appearance_feet_id",       appearance.feet_id)
			remote.set("player_display_name",      PlayerIdentity.display_name)
			remote.set("player_id_short",          PlayerIdentity.id.left(4))

func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	# Handle right-click place/use (mouse button events bypass the key filter below)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_do_place_use()
			return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_do_attack()
		KEY_F:
			_do_place_use()
		KEY_C:
			# Open crafting menu or cycle to next recipe if already open.
			var cs := get_node_or_null("../CraftingSystem")
			if cs != null:
				if cs.get("is_open"):
					cs.call("_cycle", 1)
				else:
					cs.call("open_menu")
			else:
				# Fallback: open CraftingUI if present.
				var cui := get_node_or_null("../CraftingUI")
				if cui != null:
					cui.call("toggle")
		KEY_L:
			# Toggle lantern — mirrors whether lantern tool is in action bar.
			if _lantern != null:
				_lantern.toggle()
		KEY_F12:
			# Save a screenshot to user://screenshots/ so the laptop's
			# dev/play.sh can rsync it back to the dev server for review.
			_save_screenshot()
		KEY_T:
			# Open chat input. CanvasLayer has no is_visible_in_tree(); use .visible.
			var chat_input := get_node_or_null("../ChatInput")
			if chat_input != null and not chat_input.visible:
				chat_input.call("activate")
				get_viewport().set_input_as_handled()
		KEY_TAB:
			# Toggle chat history panel.
			var history := get_node_or_null("../ChatHistoryPanel")
			if history != null:
				history.call("toggle")
				get_viewport().set_input_as_handled()
		KEY_Y:
			# Toggle talisman dormant/awakened.
			if inventory != null:
				var awakened: bool = inventory.toggle_talisman()
				_on_talisman_toggled(awakened)
		KEY_1:
			# Select tool slot 0 (lantern by default).
			if inventory != null:
				inventory.select_tool(0)
		KEY_2:
			# Select tool slot 1 (shovel by default).
			if inventory != null:
				inventory.select_tool(1)
		KEY_I:
			# Toggle EquipmentUI — handled by EquipmentUI node when it exists.
			var ui := get_node_or_null("../EquipmentUI")
			if ui != null:
				ui.call("toggle")
		KEY_E:
			# Open workbench if standing within 2 tiles of one.
			_try_open_workbench()
		KEY_ENTER, KEY_KP_ENTER:
			# Enter is handled by ChatInput's LineEdit when chat is active.
			pass

func _on_talisman_toggled(awakened: bool) -> void:
	# Notify coordinator so the reputation gate reflects talisman state.
	# The coordinator already checks the reputation store on each merge attempt;
	# awakening/dormanting just changes what the talisman does passively.
	print("Player: talisman %s" % ("awakened" if awakened else "dormant"))
	# Future: emit signal for HUD, VibeBus, visual effect.

## Check tiles within 2-tile radius for a workbench (atlas 1,2 on object layer).
## If found, opens the CraftingUI in workbench mode.
func _try_open_workbench() -> void:
	var tile_pos := Vector2i(int(floorf(position.x / Constants.TILE_SIZE)),
	                         int(floorf(position.y / Constants.TILE_SIZE)))
	const WORKBENCH_RANGE := 2
	for dy in range(-WORKBENCH_RANGE, WORKBENCH_RANGE + 1):
		for dx in range(-WORKBENCH_RANGE, WORKBENCH_RANGE + 1):
			var check_pos := tile_pos + Vector2i(dx, dy)
			var tile: Dictionary = chunk_manager.get_object_tile_at(check_pos)
			if tile.is_empty():
				continue
			var atlas := Vector2i(int(tile.get("atlas_x", -1)), int(tile.get("atlas_y", -1)))
			if atlas == Vector2i(1, 2):  # workbench
				var cui := get_node_or_null("../CraftingUI")
				if cui != null:
					cui.call("open_workbench")
				return

## Called by World when ShrineManager.buffs_changed fires.
## Updates appearance so CharacterRenderer switches to mod visuals.
func _on_buffs_changed(buffs: Array) -> void:
	if appearance == null:
		return
	appearance.active_buff_ids.clear()
	for b in buffs:
		appearance.active_buff_ids.append(str(b["buff_id"]))
	# Resolve body + held item from active buffs via unified slot resolver.
	appearance.base_body_id = AssetPackScript.resolve_slot_for_buffs("body", appearance.active_buff_ids)
	# Buff-granted item is cosmetic — shows while in shrine, independent of active tool.
	# Functional tool sprites (lantern lit, shovel raised) are a future layer on top.
	appearance.held_item_id = AssetPackScript.resolve_slot_for_buffs("held_item", appearance.active_buff_ids)

## Eat the first food-category item in the bag, restoring 30 food.
func _try_eat() -> void:
	if inventory == null:
		return
	# Search bag for the first food-category item.
	var food_id: String = ""
	for i in range(inventory.BAG_SIZE):
		var slot: Dictionary = inventory.bag[i] as Dictionary
		if slot.is_empty():
			continue
		if str(slot.get("category", "")) == "food":
			food_id = str(slot.get("id", ""))
			break
	if food_id == "":
		print("Player: nothing to eat")
		return
	inventory.remove_from_bag(food_id, 1)
	food = min(food + 30, max_food)
	_pickup_flash_timer = PICKUP_FLASH_DURATION
	print("Player: ate %s, food=%d/%d" % [food_id, food, max_food])

func _check_item_pickup(tile_pos: Vector2i) -> void:
	if not chunk_manager.has_tile_at(tile_pos, 1):
		return
	var chunk := chunk_manager.get_chunk(CoordUtils.world_to_chunk(tile_pos))
	if chunk == null:
		return
	var local := CoordUtils.world_to_local(tile_pos)
	var tile: Dictionary = chunk.crdt.get_tile(1, local)
	if tile.is_empty():
		return
	var ax: int = tile.get("atlas_x", -1)
	var ay: int = tile.get("atlas_y", -1)
	if ax == 3 and ay == 1:
		# loot_pickup tile — basic materials
		chunk_manager.remove_tile(tile_pos, 1, "pickup")
		_pickup_flash_timer = PICKUP_FLASH_DURATION
		if inventory != null:
			inventory.add_to_bag({"id": "wood",  "category": "material", "count": 2}, 32)
			inventory.add_to_bag({"id": "stone", "category": "material", "count": 2}, 32)
			print("Player: picked up loot (2 wood, 2 stone)")
	elif ax == 3 and ay == 2:
		# ether_crystal — shifting lands unique reward
		chunk_manager.remove_tile(tile_pos, 1, "pickup")
		_pickup_flash_timer = PICKUP_FLASH_DURATION
		if inventory != null:
			inventory.add_to_bag({"id": "ether_crystal", "category": "material", "count": 1}, 16)
			print("Player: picked up ether_crystal")
	elif ax == 1 and ay == 2:
		# marrow_drop — dropped by Wisp on death
		chunk_manager.remove_tile(tile_pos, 1, "pickup")
		_pickup_flash_timer = PICKUP_FLASH_DURATION
		if inventory != null:
			inventory.add_to_bag({"id": "marrow", "category": "material", "count": 1}, 10)
			print("Player: picked up marrow")
	elif ax == 2 and ay == 2:
		# moonstone_patch — crystallised by Pale, harvestable at night only
		chunk_manager.remove_tile(tile_pos, 1, "pickup")
		_pickup_flash_timer = PICKUP_FLASH_DURATION
		if inventory != null:
			inventory.add_to_bag({"id": "moonstone", "category": "material", "count": 1}, 10)
			print("Player: harvested moonstone")

## Active SpeechBubble nodes above this player (for stacking).
var _speech_bubbles: Array = []

const SpeechBubbleScript := preload("res://ui/SpeechBubble.gd")

## Called when ChatSystem emits message_received.
## Spawns a speech bubble on the correct node (self or a RemotePlayer).
## History panel is wired separately in World._setup_chat_system — do NOT call
## add_message here or every message appears twice.
func _on_chat_message(sender_name: String, text: String, is_dm: bool, sender_id: String) -> void:
	# Determine which node should display the bubble
	var target_node: Node2D = null
	var my_id: String = PlayerIdentity.id
	if sender_id == my_id or sender_id == "":
		target_node = self
	else:
		# Try to find a RemotePlayer node with matching id
		for child in get_parent().get_children():
			if child.get("id") == sender_id:
				target_node = child as Node2D
				break
		# Fallback: own node if sender not found (e.g. system messages)
		if target_node == null and sender_id.is_empty():
			target_node = self

	if target_node == null:
		return

	_spawn_bubble_on(target_node, sender_name, text, is_dm)

func _spawn_bubble_on(target: Node2D, sender_name: String, text: String, is_dm: bool) -> void:
	# Clean up freed bubbles first
	_speech_bubbles = _speech_bubbles.filter(func(b): return is_instance_valid(b))

	var bubble := SpeechBubbleScript.new()
	target.add_child(bubble)
	bubble.setup(text, sender_name, is_dm)

	# Stack above existing bubbles (most recent at bottom, older shift up)
	var stack_offset: float = 24.0  # base offset above player head
	for existing in _speech_bubbles:
		if is_instance_valid(existing) and existing.get_parent() == target:
			existing.position.y -= bubble.bubble_height + 2.0

	bubble.position = Vector2(0.0, -stack_offset)
	if target == self:
		_speech_bubbles.append(bubble)

func _update_appearance() -> void:
	if appearance == null or _renderer == null:
		return
	# Held item: buff-granted item takes priority (cosmetic shrine visual).
	# Falls back to active inventory tool when no buff overrides.
	if appearance.held_item_id == "":
		var active_tool: Dictionary = inventory.get_active_tool() if inventory != null else {}
		appearance.held_item_id = str(active_tool.get("id", "")) if not active_tool.is_empty() else ""
	# Mirror equipment slots into appearance.
	if equipment != null:
		appearance.armor_id = equipment.get_equipped("armor")
		appearance.head_id  = equipment.get_equipped("head")
		appearance.feet_id  = equipment.get_equipped("feet")
	_renderer.refresh(appearance)
