## TileHitFlash — brief visual overlay on a tile hit.
## Spawned at tile world coords (top-left corner) by TileInteraction.
## Fades from initial alpha to zero over _duration seconds, then self-destructs.
##
## Usage:
##   var flash := TileHitFlashScript.new()
##   flash.setup(Color(1, 1, 1, 0.45))           # normal hit — white flash
##   flash.setup(Color(1, 0.2, 0.2, 0.55), 0.8)  # last hit — red lingers
##   flash.position = Vector2(tile_pos) * TILE_SIZE
##   world.add_child(flash)
extends Node2D

const TILE_PX: int = 16  # mirrors Constants.TILE_SIZE; no autoload dep needed

var _color: Color = Color.WHITE
var _start_alpha: float = 0.45
var _duration: float = 0.15
var _timer: float = 0.15

## Call before adding to the scene tree.
func setup(col: Color, duration: float = 0.15) -> void:
	_color = col
	_start_alpha = col.a
	_duration = duration
	_timer = duration
	z_index = 3  # above tiles (0,1) and player (2)

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return
	_color.a = _start_alpha * (_timer / _duration)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, TILE_PX, TILE_PX), _color)
