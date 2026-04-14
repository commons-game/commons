## Player — top-down WASD movement. Notifies ChunkManager of position each tick.
extends CharacterBody2D

const SPEED := 80.0

## Filled circle radius and direction-triangle half-width (in pixels).
const RADIUS := 7.0
const TRI_SIZE := 4.0

## Track last non-zero velocity for the direction indicator.
var _facing := Vector2.UP

const ShrineManagerScript := preload("res://mods/ShrineManager.gd")

@onready var chunk_manager: ChunkManager    = $"../ChunkManager"
@onready var shrine_manager: ShrineManagerScript = $"../ShrineManager"

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
	# Push our position to our RemotePlayer so the synchronizer can broadcast it.
	# Works for both host (RemotePlayer_1) and clients (RemotePlayer_<id>).
	# get_node_or_null is a no-op in single-player (no RemotePlayer exists).
	var own_id := multiplayer.get_unique_id()
	var remote := get_node_or_null("../RemotePlayer_%d" % own_id)
	if remote:
		remote.position = global_position
