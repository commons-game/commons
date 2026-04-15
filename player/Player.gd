## Player — top-down WASD movement. Notifies ChunkManager of position each tick.
extends CharacterBody2D

const SPEED := 80.0

## Filled circle radius and direction-triangle half-width (in pixels).
const RADIUS := 7.0
const TRI_SIZE := 4.0

## Track last non-zero velocity for the direction indicator.
var _facing := Vector2.UP
## Set by World._setup_merge_system() after both Player and MergeCoordinator are ready.
var coordinator: Node = null
var _last_chunk: Vector2i = Vector2i(-9999, -9999)

## Walk animation: accumulates distance moved to drive frame changes.
var _walk_dist: float = 0.0
## Distance per walk frame step (pixels). At SPEED=80 this cycles ~every 0.15s.
const WALK_STEP := 12.0

const ShrineManagerScript       := preload("res://mods/ShrineManager.gd")
const LanternScript             := preload("res://player/Lantern.gd")
const CharacterAppearanceScript := preload("res://player/CharacterAppearance.gd")
const CharacterRendererScript   := preload("res://player/CharacterRenderer.gd")
const AssetPackScript           := preload("res://player/AssetPack.gd")
const InventoryScript           := preload("res://items/Inventory.gd")

@onready var chunk_manager: ChunkManager    = $"../ChunkManager"
@onready var shrine_manager: ShrineManagerScript = $"../ShrineManager"

var inventory: Object = null  # Inventory — set up in _ready
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

	_lantern = LanternScript.new()
	_lantern.name = "Lantern"
	add_child(_lantern)

func _draw() -> void:
	# Suppress draw-code when CharacterRenderer has a sprite showing.
	if _renderer != null and _renderer.has_visible_sprites():
		return
	# Fallback: white filled circle with dark outline + direction triangle.
	# Active when no sprite sheet is loaded (renderer not ready, or pack returns null).
	draw_circle(Vector2.ZERO, RADIUS, Color(0.15, 0.15, 0.15))   # shadow/outline
	draw_circle(Vector2.ZERO, RADIUS - 1.0, Color.WHITE)
	# Direction triangle: small filled triangle pointing in _facing direction
	var tip   := _facing * (RADIUS + TRI_SIZE)
	var left  := _facing.rotated(deg_to_rad( 140.0)) * (TRI_SIZE * 0.8)
	var right := _facing.rotated(deg_to_rad(-140.0)) * (TRI_SIZE * 0.8)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.9, 0.7, 0.1))

func _process(_delta: float) -> void:
	queue_redraw()

func _physics_process(_delta: float) -> void:
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

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
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
	# Resolve body variant from active buffs (e.g. blood_harvest → necromancer).
	appearance.body_id = AssetPackScript.resolve_body_for_buffs(appearance.active_buff_ids)

func _update_appearance() -> void:
	if appearance == null or _renderer == null:
		return
	# Held item from active inventory slot
	var active_tool: Dictionary = inventory.get_active_tool() if inventory != null else {}
	appearance.held_item_id = str(active_tool.get("id", "")) if not active_tool.is_empty() else ""
	_renderer.refresh(appearance)
