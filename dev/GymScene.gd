## GymScene — playable collision test environment.
##
## Rock box: 8×8 tile area, player starts inside, cannot escape.
## Use WASD / arrow keys. Player position shown in HUD.
## ESC or F5 to quit.
##
## Run from exported binary:
##   DISPLAY=:100 ./freeland.x86_64 --rendering-driver opengl3 -- --dev-gym
## Run from editor:
##   DISPLAY=:100 ~/bin/godot4 --rendering-driver opengl3 --path . -- --dev-gym
extends Node2D

const ChunkScene      := preload("res://world/chunk/Chunk.tscn")
const GymPlayerScript := preload("res://dev/GymPlayer.gd")

const STONE := Vector2i(2, 0)
const ROCK  := Vector2i(1, 1)

var _player: CharacterBody2D = null
var _pos_label: Label = null

func _ready() -> void:
	# Gym chunk — rock border around an open stone interior.
	var chunk := ChunkScene.instantiate()
	add_child(chunk)
	(chunk as Node).call("initialize", Vector2i(0, 0), _make_gym_entries())

	# Player.
	_player = CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	var rect  := RectangleShape2D.new()
	rect.size = Vector2(12, 12)
	shape.shape = rect
	_player.add_child(shape)
	_player.set_script(GymPlayerScript)
	_player.position = Vector2(56, 56)

	# Camera attached to player so it follows.
	var cam := Camera2D.new()
	cam.zoom = Vector2(5, 5)
	_player.add_child(cam)

	add_child(_player)

	# HUD overlay.
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.custom_minimum_size = Vector2(310, 70)
	bg.position = Vector2(4, 4)
	canvas.add_child(bg)

	_pos_label = Label.new()
	_pos_label.position = Vector2(8, 8)
	_pos_label.add_theme_font_size_override("font_size", 12)
	_pos_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	canvas.add_child(_pos_label)

func _process(_delta: float) -> void:
	if _player != null and _pos_label != null:
		var p := _player.position
		# Box collision edges: roughly x[19..109], y[22..114]
		var inside := p.x > 19 and p.x < 109 and p.y > 22 and p.y < 114
		_pos_label.text = (
			"COLLISION GYM  |  ESC to quit\n"
			+ "pos: (%.1f, %.1f)   %s\n"
			+ "Rock box: tiles 0 and 7 on all sides"
		) % [p.x, p.y, "[INSIDE]" if inside else "[!!! ESCAPED — collision broken !!!]"]

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	if (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_F5]:
		get_tree().quit()

func _make_gym_entries() -> Dictionary:
	var entries := {}
	for y in range(8):
		for x in range(8):
			var gkey := CoordUtils.make_crdt_key(0, x, y)
			entries[gkey] = {"tile_id": 0, "atlas_x": STONE.x, "atlas_y": STONE.y,
			                 "alt_tile": 0, "timestamp": 0.0, "author_id": ""}
			if x == 0 or x == 7 or y == 0 or y == 7:
				var rkey := CoordUtils.make_crdt_key(1, x, y)
				entries[rkey] = {"tile_id": 0, "atlas_x": ROCK.x, "atlas_y": ROCK.y,
				                 "alt_tile": 0, "timestamp": 0.0, "author_id": ""}
	return entries
