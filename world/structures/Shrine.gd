## Shrine — territory anchor. An independent world entity; no player owns it.
##
## Visual: a large crystalline hexagonal spike (Still, pale blue/white) at the
## center, plus 3 Bloom tendrils (yellow-green arcs) that rotate around it.
## Rotation speed scales with power; at power=0 they barely move, at power=1
## they spin visibly.
##
## Mechanics:
##   - TERRITORY_RADIUS (8 tiles) defines the Shrine's area of influence.
##   - power (0.0–1.0) grows when players are present, drains when absent.
##   - hp = 100; requires flint_knife to damage.
##   - On hp <= 0: requests the tile be removed via TileMutationBus. The bus
##     fires tile_removed and ChunkManager frees this scene.
##   - Registers with ShrineRegistry keyed by world_tile_pos.
extends Node2D

## World-tile position. Set by ChunkManager when spawning from CRDT.
var world_tile_pos: Vector2i = Vector2i.ZERO

## Hit points. Reduced only by flint_knife or better.
var hp: int = 100

## Territory influence radius in tiles.
const TERRITORY_RADIUS: int = 8

## Power level: 0.0 (dormant) to 1.0 (fully charged).
var power: float = 0.0

## Visual animation state.
var _anim_time: float = 0.0

## PointLight2D child — created in _ready.
var _light: PointLight2D = null

## Default light texture scale: Godot's default PointLight2D texture is 64px radius.
## We map pixel range → texture_scale via range_px / 64.0.
const LIGHT_RANGE_MIN_PX := 48.0
const LIGHT_RANGE_MAX_PX := 192.0
const LIGHT_ENERGY_MIN   := 0.3
const LIGHT_ENERGY_MAX   := 2.5
const LIGHT_COLOR_STILL  := Color(0.6, 0.8, 1.0)   # pale blue (dormant)
const LIGHT_COLOR_BLOOM  := Color(0.7, 1.0, 0.7)   # warm green-white (full power)

func _ready() -> void:
	z_index = 2
	# Create and attach the PointLight2D.
	_light = PointLight2D.new()
	_light.name = "ShrineLight"
	# No explicit texture set — Godot uses its built-in default white circle texture.
	_light.color = LIGHT_COLOR_STILL
	_light.energy = LIGHT_ENERGY_MIN
	_light.texture_scale = LIGHT_RANGE_MIN_PX / 64.0
	add_child(_light)

	ShrineRegistry.register_shrine(world_tile_pos, self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		ShrineRegistry.unregister_shrine(world_tile_pos)

func _process(delta: float) -> void:
	_anim_time += delta
	_power_tick(delta)
	_update_light()
	queue_redraw()

## Update power based on nearby players. Called by _process.
## World.gd passes nearby player count via notify_players_nearby; this method
## also accepts direct delta updates when called directly.
var _nearby_players: int = 0

## Called by World._process with the count of players within TERRITORY_RADIUS.
func notify_players_nearby(count: int) -> void:
	_nearby_players = count

func _power_tick(delta: float) -> void:
	if _nearby_players > 0:
		# Each present player contributes 0.02/s, so ~50s solo to reach 1.0.
		power += 0.02 * _nearby_players * delta
	else:
		# Slow decay when no players present.
		power -= 0.005 * delta
	power = clamp(power, 0.0, 1.0)

func _update_light() -> void:
	if _light == null:
		return
	_light.energy = lerp(LIGHT_ENERGY_MIN, LIGHT_ENERGY_MAX, power)
	var range_px: float = lerp(LIGHT_RANGE_MIN_PX, LIGHT_RANGE_MAX_PX, power)
	_light.texture_scale = range_px / 64.0
	_light.color = LIGHT_COLOR_STILL.lerp(LIGHT_COLOR_BLOOM, power)

## Apply damage to this Shrine.
## attacker_tool: the id string of the tool being used (e.g. "flint_knife").
## Returns false if the tool is insufficient (bare hands), true if damage was applied.
func take_damage(amount: int, attacker_tool: String) -> bool:
	if attacker_tool != "flint_knife":
		print("Shrine: Need a flint tool to damage this.")
		return false
	hp = max(0, hp - amount)
	print("Shrine: took %d damage, hp=%d" % [amount, hp])
	if hp <= 0:
		var bus: Node = get_tree().root.find_child("TileMutationBus", true, false)
		if bus != null:
			bus.request_remove_tile(world_tile_pos, 1)
		else:
			queue_free()  # isolation fallback
	return true

func _draw() -> void:
	# -----------------------------------------------------------------------
	# Still — crystalline hexagonal spike: pale blue/white, pointing upward.
	# Larger than Tether (~14px tall spike body).
	# -----------------------------------------------------------------------

	# Outer glow: soft blue radial haze, pulsing slightly with power.
	var glow_r: float = 14.0 + power * 6.0
	draw_circle(Vector2.ZERO, glow_r, Color(0.55, 0.75, 1.0, 0.15 + power * 0.1))

	# Crystal body: a narrow hexagonal shard pointing upward.
	var crystal := PackedVector2Array([
		Vector2(  0.0, -14.0),   # tip
		Vector2(  5.0,  -6.0),   # upper-right
		Vector2(  4.5,   3.0),   # lower-right
		Vector2(  0.0,   6.0),   # base-center
		Vector2( -4.5,   3.0),   # lower-left
		Vector2( -5.0,  -6.0),   # upper-left
	])
	draw_colored_polygon(crystal, Color(0.82, 0.93, 1.0, 0.94))

	# Inner highlight facet (light catching from upper-left).
	var facet := PackedVector2Array([
		Vector2(-1.0, -13.0),
		Vector2( 1.5,  -6.0),
		Vector2(-1.5,  -3.0),
		Vector2(-4.0,  -7.0),
	])
	draw_colored_polygon(facet, Color(1.0, 1.0, 1.0, 0.6))

	# Crisp outline.
	for i in range(crystal.size()):
		var a: Vector2 = crystal[i]
		var b: Vector2 = crystal[(i + 1) % crystal.size()]
		draw_line(a, b, Color(0.45, 0.65, 0.95, 0.85), 1.0)

	# Power-glow core: small inner circle that brightens with power.
	if power > 0.05:
		draw_circle(Vector2(0.0, -3.0), 2.5 + power * 3.0,
		            Color(0.8, 0.95, 1.0, 0.4 + power * 0.4))

	# -----------------------------------------------------------------------
	# Bloom — 3 rotating tendril arcs. Speed scales with power.
	# At power=0: rotation_speed ≈ 0.15 rad/s (barely visible drift).
	# At power=1: rotation_speed ≈ 1.8 rad/s (clearly spinning).
	# -----------------------------------------------------------------------
	var rotation_speed: float = lerp(0.15, 1.8, power)
	var tendril_base_r: float = 10.0      # orbit radius
	var seg_count := 16                   # arc segments per tendril
	var arc_span: float = TAU / 3.0 * 0.85  # each tendril covers 85% of its 120° sector

	var tendril_alpha: float = 0.5 + power * 0.35
	var tendril_width: float = 1.5 + power * 1.5

	for t in range(3):
		var base_angle: float = (float(t) / 3.0) * TAU + _anim_time * rotation_speed

		var prev_pt: Vector2 = Vector2.ZERO
		for i in range(seg_count + 1):
			var frac: float = float(i) / seg_count
			var angle: float = base_angle + (frac - 0.5) * arc_span
			# Tendril curves slightly inward at ends, outward at center.
			var r: float = tendril_base_r + sin(frac * PI) * 3.5
			var pt := Vector2(cos(angle) * r, sin(angle) * r)
			if i > 0:
				draw_line(prev_pt, pt,
				          Color(0.3, 0.9, 0.3, tendril_alpha * (0.5 + sin(frac * PI) * 0.5)),
				          tendril_width)
			prev_pt = pt

		# Knob at the arc midpoint.
		var mid_angle: float = base_angle
		var knob_pos := Vector2(cos(mid_angle) * (tendril_base_r + 3.5),
		                        sin(mid_angle) * (tendril_base_r + 3.5))
		draw_circle(knob_pos, tendril_width * 0.85,
		            Color(0.2, 0.85, 0.3, tendril_alpha))
