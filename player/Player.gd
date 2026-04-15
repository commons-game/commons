## Player — top-down WASD movement. Notifies ChunkManager of position each tick.
extends CharacterBody2D

const SPEED := 80.0

var hp: int = 100
var max_hp: int = 100
var _dead: bool = false

const ATTACK_DAMAGE := 25
const ATTACK_RANGE := 1.5  # tiles

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
	for i in range(steps):
		var offset := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(_camera, "offset", offset, step_time)
	tween.tween_property(_camera, "offset", Vector2.ZERO, step_time)

func _on_player_died() -> void:
	_dead = true
	print("Player: died — starting respawn sequence")

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

	# Wait a moment at full black.
	await get_tree().create_timer(0.4).timeout

	# Reset player state.
	hp = max_hp
	position = Vector2.ZERO

	# Fade back in.
	_dead = false
	var tween2 := create_tween()
	tween2.tween_property(overlay, "color", Color(0, 0, 0, 0), 0.6)
	await tween2.finished

	overlay_layer.queue_free()

func _do_attack() -> void:
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 0.5
	_attack_arc_timer = ATTACK_ARC_DURATION
	var tile_pos := Vector2i(int(floorf(position.x / Constants.TILE_SIZE)),
	                         int(floorf(position.y / Constants.TILE_SIZE)))
	# Find any mob within ATTACK_RANGE tiles — duck-type check via "mob_died" signal
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
				health.call("take_damage", ATTACK_DAMAGE)

func _process(delta: float) -> void:
	queue_redraw()
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	_damage_flash_timer = maxf(_damage_flash_timer - delta, 0.0)
	_pickup_flash_timer = maxf(_pickup_flash_timer - delta, 0.0)
	_attack_arc_timer   = maxf(_attack_arc_timer   - delta, 0.0)

func _physics_process(_delta: float) -> void:
	if _dead:
		return
	var input := Vector2(Input.get_axis("ui_left", "ui_right"),
	                     Input.get_axis("ui_up", "ui_down"))
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

func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_do_attack()
		KEY_L:
			# Toggle lantern — mirrors whether lantern tool is in action bar.
			if _lantern != null:
				_lantern.toggle()
		KEY_T:
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

func _on_talisman_toggled(awakened: bool) -> void:
	# Notify coordinator so the reputation gate reflects talisman state.
	# The coordinator already checks the reputation store on each merge attempt;
	# awakening/dormanting just changes what the talisman does passively.
	print("Player: talisman %s" % ("awakened" if awakened else "dormant"))
	# Future: emit signal for HUD, VibeBus, visual effect.

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
	# Atlas (3,1) = loot_pickup → bone_armor for now
	if tile.get("atlas_x", -1) == 3 and tile.get("atlas_y", -1) == 1:
		chunk_manager.remove_tile(tile_pos, 1, "pickup")
		_pickup_flash_timer = PICKUP_FLASH_DURATION
		if equipment != null:
			equipment.call("add_to_bag", "bone_armor", "armor")
			print("Player: picked up bone_armor")

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
