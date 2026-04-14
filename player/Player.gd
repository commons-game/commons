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

const ShrineManagerScript := preload("res://mods/ShrineManager.gd")
const LanternScript       := preload("res://player/Lantern.gd")
const InventoryScript     := preload("res://items/Inventory.gd")

@onready var chunk_manager: ChunkManager    = $"../ChunkManager"
@onready var shrine_manager: ShrineManagerScript = $"../ShrineManager"

var inventory: Object = null  # Inventory — set up in _ready
var _lantern: Node = null

func _ready() -> void:
	inventory = InventoryScript.new()
	# Starter loadout: lantern in slot 0, shovel in slot 1.
	inventory.set_tool_slot(0, {"id": "lantern", "category": "tool", "count": 1})
	inventory.set_tool_slot(1, {"id": "shovel",  "category": "tool", "count": 1})

	_lantern = LanternScript.new()
	_lantern.name = "Lantern"
	add_child(_lantern)

func _draw() -> void:
	# Body: white filled circle with dark outline
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
	# get_node_or_null is a no-op in single-player (no RemotePlayer exists).
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
