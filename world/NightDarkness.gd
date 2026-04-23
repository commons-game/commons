## NightDarkness — dims the world at night using CanvasModulate + player ambient light.
##
## At day:   CanvasModulate is white (no effect).
## At night: CanvasModulate transitions to dark blue-grey; a PointLight2D on the
##           player gives ~2-tile ambient glow so you can just see what's touching you.
##
## Campfires already carry their own PointLight2D (see Campfire.gd). The lantern
## item will extend the player light when equipped (TODO: wire in Player._update_appearance).
##
## Not an autoload. Instantiated and wired by World._setup_day_night_system().
## Set `player` before add_child.
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
var _player_light: PointLight2D = null
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
		if player != null and _player_light == null:
			_attach_player_light()

func _on_phase_changed(is_day: bool) -> void:
	_is_night = not is_day
	var target_color: Color
	if is_day:
		target_color = COLOR_DAY
	else:
		target_color = ambient_night_color(DayClock.moon_fullness())
	var tween := get_tree().create_tween()
	tween.tween_property(_modulate, "color", target_color, FADE_DURATION)

	# Wire player light on first night if not done yet.
	if not is_day and _player_light == null and player != null:
		_attach_player_light()

## Visible lantern radius in tiles. 16 px/tile × 8 tiles = 128 px radius → 256 px diameter.
const LANTERN_TILE_RADIUS := 8

func _attach_player_light() -> void:
	_player_light = PointLight2D.new()
	_player_light.name = "AmbientGlow"
	# Lantern: see ground + approaching mobs, not the distance.
	# Texture is 128 px; scale 2.0 → 256 px diameter = 8 tile radius.
	_player_light.texture = _make_radial_texture(128)
	_player_light.texture_scale = 2.0
	_player_light.energy = 0.85
	_player_light.color = Color(0.95, 0.82, 0.55)  # warm lantern glow
	_player_light.shadow_enabled = false
	player.add_child(_player_light)

## Build a simple radial gradient texture for the point light.
static func _make_radial_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius  := size * 0.5
	for y in range(size):
		for x in range(size):
			var dist: float = Vector2(x, y).distance_to(center)
			var alpha: float = clampf(1.0 - dist / radius, 0.0, 1.0)
			alpha = alpha * alpha  # quadratic falloff — sharper edge
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(img)
