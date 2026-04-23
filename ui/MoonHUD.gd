## MoonHUD — small moon-phase indicator in the top-right corner.
##
## The moon is the only UI for moon state. See docs/game_design.md § Moon phases.
## Renders the lit portion of the moon as a polygon bounded by the outer limb
## (semicircle on the lit side) and the terminator ellipse (curve between lit and dark).
##
## Not an autoload. Instantiated by World._setup_day_night_system().
extends CanvasLayer

const RADIUS      := 10.0
const MARGIN      := 14.0
const SEG         := 32
const COLOR_LIT   := Color(0.96, 0.94, 0.80)  # pale lunar cream
const COLOR_DARK  := Color(0.12, 0.13, 0.19)  # near-black — dark side of moon
const COLOR_RING  := Color(0.55, 0.58, 0.70, 0.8)

var _face: Control = null

func _ready() -> void:
	layer = 20
	_face = Control.new()
	_face.name = "MoonFace"
	_face.custom_minimum_size = Vector2(RADIUS * 2 + 4, RADIUS * 2 + 4)
	_face.draw.connect(_draw_face)
	add_child(_face)
	_reposition()
	get_viewport().size_changed.connect(_reposition)

func _process(_delta: float) -> void:
	if _face != null:
		_face.queue_redraw()

func _reposition() -> void:
	if _face == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_face.position = Vector2(vp.x - RADIUS * 2 - MARGIN, MARGIN)

func _draw_face() -> void:
	var c := Vector2(RADIUS + 2, RADIUS + 2)
	var phase := DayClock.moon_phase()
	var fullness: float = DayClock.moon_fullness()

	# Full disk in dark colour first — this is the moon silhouette.
	_face.draw_circle(c, RADIUS, COLOR_DARK)

	if phase == 0:
		_face.draw_arc(c, RADIUS, 0.0, TAU, SEG, COLOR_RING, 1.2)
		return
	if phase == 4:
		_face.draw_circle(c, RADIUS, COLOR_LIT)
		_face.draw_arc(c, RADIUS, 0.0, TAU, SEG, COLOR_RING, 1.2)
		return

	# Intermediate phases: draw the lit region as a polygon.
	# Waxing (phases 1..3): lit on the right. Waning (5..7): lit on the left.
	var waxing := phase < 4
	var lit_side: float = 1.0 if waxing else -1.0
	_face.draw_colored_polygon(_build_lit_polygon(c, lit_side, fullness), COLOR_LIT)
	_face.draw_arc(c, RADIUS, 0.0, TAU, SEG, COLOR_RING, 1.2)

## Lit-region polygon: perimeter of lit semicircle + terminator ellipse arc.
## fullness is the moon_fullness() scalar, which equals the illumination fraction
## for non-new, non-full phases (0.25 or 0.75 at the cardinal phases).
func _build_lit_polygon(center: Vector2, lit_side: float, fullness: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	# Terminator horizontal semi-axis (signed).
	# For waxing (lit_side=+1): term_x = (1 - 2*f) * R
	#   f=0   → +R  (terminator at right limb → fully dark)
	#   f=0.25→ +0.5R (crescent — terminator bulges INTO lit side, thin crescent on right)
	#   f=0.5 →  0   (half moon — straight terminator)
	#   f=0.75→ -0.5R (gibbous — terminator bulges into dark side, thin dark crescent on left)
	#   f=1   → -R  (fully lit)
	# For waning (lit_side=-1): mirror.
	var term_x := (1.0 - 2.0 * fullness) * RADIUS * lit_side

	# Outer limb on the lit side: from top (0, -R) to bottom (0, +R) via the lit edge.
	for i in range(SEG + 1):
		var t := float(i) / float(SEG)
		var angle := -PI / 2.0 + t * PI  # -π/2 → π/2
		var x := cos(angle) * RADIUS * lit_side
		var y := sin(angle) * RADIUS
		pts.append(center + Vector2(x, y))

	# Terminator ellipse: from bottom (0, +R) back to top (0, -R).
	for i in range(SEG + 1):
		var t := float(i) / float(SEG)
		var angle := PI / 2.0 - t * PI
		var x := term_x * cos(angle)
		var y := RADIUS * sin(angle)
		pts.append(center + Vector2(x, y))
	return pts
