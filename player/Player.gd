## Player — top-down WASD movement. Notifies ChunkManager of position each tick.
extends CharacterBody2D

const SPEED := 80.0

@onready var chunk_manager: ChunkManager = $"../ChunkManager"

func _physics_process(_delta: float) -> void:
	velocity = Vector2(Input.get_axis("ui_left", "ui_right"),
	                   Input.get_axis("ui_up", "ui_down")).normalized() * SPEED
	move_and_slide()
	var tile_pos := Vector2i(int(floorf(position.x / Constants.TILE_SIZE)),
	                         int(floorf(position.y / Constants.TILE_SIZE)))
	chunk_manager.update_player_position(tile_pos)
	chunk_manager.update_player_last_visited(tile_pos)
