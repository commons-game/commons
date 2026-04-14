## RenderGym — visual ground truth for every tile type.
##
## Displays one of each tile type in a row so you can verify the full tileset
## atlas renders correctly. If any tile looks wrong (wrong color, missing art,
## solid block, invisible) you know the atlas or TileSet setup is broken.
##
## Run:
##   DISPLAY=:100 ./freeland.x86_64 --rendering-driver opengl3 -- --dev-render-gym
##
## Layout (left to right, each tile 16px):
##   [0] grass  (0,0)  ground only
##   [1] dirt   (1,0)  ground only
##   [2] stone  (2,0)  ground only
##   [3] water  (3,0)  ground only
##   [4] tree   (0,1)  on grass ground — object layer
##   [5] rock   (1,1)  on stone ground — object layer
##
## ESC / F5 to quit.
extends Node2D

const ChunkScene := preload("res://world/chunk/Chunk.tscn")

const SHOWCASE := [
	{"name": "grass", "ground": Vector2i(0, 0), "object": null},
	{"name": "dirt",  "ground": Vector2i(1, 0), "object": null},
	{"name": "stone", "ground": Vector2i(2, 0), "object": null},
	{"name": "water", "ground": Vector2i(3, 0), "object": null},
	{"name": "tree",  "ground": Vector2i(0, 0), "object": Vector2i(0, 1)},
	{"name": "rock",  "ground": Vector2i(2, 0), "object": Vector2i(1, 1)},
]

func _ready() -> void:
	var entries := {}
	for i in range(SHOWCASE.size()):
		var spec: Dictionary = SHOWCASE[i]
		# Ground tile at (i, 0)
		entries[CoordUtils.make_crdt_key(0, i, 0)] = {
			"tile_id": 0, "atlas_x": spec["ground"].x, "atlas_y": spec["ground"].y,
			"alt_tile": 0, "timestamp": 0.0, "author_id": ""}
		# Optional object tile on top
		if spec["object"] != null:
			entries[CoordUtils.make_crdt_key(1, i, 0)] = {
				"tile_id": 0, "atlas_x": spec["object"].x, "atlas_y": spec["object"].y,
				"alt_tile": 0, "timestamp": 0.0, "author_id": ""}

	var chunk := ChunkScene.instantiate()
	add_child(chunk)
	(chunk as Node).call("initialize", Vector2i(0, 0), entries)

	# Fixed camera centered on the tile row.
	# 6 tiles × 16px = 96px wide; center = (48, 8).
	var cam := Camera2D.new()
	cam.zoom = Vector2(8, 8)
	cam.position = Vector2(48, 8)
	add_child(cam)

	_build_hud()

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.custom_minimum_size = Vector2(420, 160)
	bg.position = Vector2(4, 4)
	canvas.add_child(bg)

	var label := Label.new()
	label.position = Vector2(10, 8)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.8))

	var lines := ["RENDER GYM  |  ESC to quit", ""]
	lines.append("Each tile is rendered at atlas coords shown.")
	lines.append("Wrong art, missing texture, or solid block = tileset bug.")
	lines.append("")
	for i in range(SHOWCASE.size()):
		var spec: Dictionary = SHOWCASE[i]
		var obj_str := ""
		if spec["object"] != null:
			obj_str = "  +obj(%d,%d)" % [spec["object"].x, spec["object"].y]
		lines.append("[%d] %-6s  ground(%d,%d)%s" % [
			i, spec["name"], spec["ground"].x, spec["ground"].y, obj_str])

	label.text = "\n".join(lines)
	canvas.add_child(label)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_F5]:
			get_tree().quit()
