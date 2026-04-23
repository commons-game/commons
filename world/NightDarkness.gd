## NightDarkness — dims the world at night using a CanvasModulate.
##
## At day:   CanvasModulate is white (no effect).
## At night: CanvasModulate transitions to a moon-scaled dark tint. The player
##           sees local surroundings only if their Lantern is lit
##           (see player/Lantern.gd — it owns the player glow).
##
## Campfires carry their own PointLight2D (see Campfire.gd).
##
## Not an autoload. Instantiated and wired by World._setup_day_night_system().
## Set `player` before add_child (kept for API compatibility; no longer used
## for attaching a light).
extends Node

var player: Node = null

## Day colour = white (normal rendering). Night colour is moon-aware:
## new moon → near-black dread; full moon → dim silver. COLOR_NIGHT is the midpoint.
const COLOR_DAY         := Color(1.0,  1.0,  1.0,  1.0)
const COLOR_NIGHT       := Color(0.08, 0.09, 0.14, 1.0)
const COLOR_NIGHT_NEW   := Color(0.04, 0.05, 0.09, 1.0)  # pitch black
const COLOR_NIGHT_FULL  := Color(0.18, 0.20, 0.28, 1.0)  # cold silver

## Seconds to fade between day and night.
const FADE_DURATION := 8.0

## Compute current moon-scaled night tint. Sampled at dusk (or mid-night init).
static func ambient_night_color(fullness: float) -> Color:
	return COLOR_NIGHT_NEW.lerp(COLOR_NIGHT_FULL, clampf(fullness, 0.0, 1.0))

var _modulate: CanvasModulate = null
var _is_night: bool = false

func _ready() -> void:
	_modulate = CanvasModulate.new()
	_modulate.color = COLOR_DAY
	if get_parent() != null:
		get_parent().add_child(_modulate)

	DayClock.phase_changed.connect(_on_phase_changed)

	# If the game launched mid-night, phase_changed never fires for dusk.
	# Apply night state immediately if it's already dark.
	await get_tree().process_frame
	if not DayClock.is_daytime():
		_modulate.color = ambient_night_color(DayClock.moon_fullness())

func _on_phase_changed(is_day: bool) -> void:
	_is_night = not is_day
	var target_color: Color
	if is_day:
		target_color = COLOR_DAY
	else:
		target_color = ambient_night_color(DayClock.moon_fullness())
	var tween := get_tree().create_tween()
	tween.tween_property(_modulate, "color", target_color, FADE_DURATION)

## Radial gradient texture helper. Shared by Lantern, Campfire, Wisp — any
## node that needs a soft circular light falloff. Kept here since historically
## NightDarkness introduced it; callers reference it by this path.
static func _make_radial_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.5
	for y in range(size):
		for x in range(size):
			var dist: float = Vector2(x, y).distance_to(center)
			var alpha: float = clampf(1.0 - dist / radius, 0.0, 1.0)
			alpha = alpha * alpha  # quadratic falloff — soft edge
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(img)
