## GymPlayer — minimal WASD CharacterBody2D for the collision gym scene.
## No dependencies on ChunkManager, ShrineManager, or any game systems.
extends CharacterBody2D

const SPEED := 80.0

func _physics_process(_delta: float) -> void:
	var input := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down"))
	velocity = input.normalized() * SPEED
	move_and_slide()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, Color(0.15, 0.15, 0.15))
	draw_circle(Vector2.ZERO, 4.0, Color.WHITE)
