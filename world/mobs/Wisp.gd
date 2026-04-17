## Wisp — tier-2 Bloom night mob. Bioluminescent, fast, drops Marrow.
##
## "Something alive that learned to glow in the dark. It can see you too."
##
## - Fast (CHASE_SPEED 95) — closes distance quickly
## - Low HP (22) — dies fast if you land hits
## - Carries a PointLight2D so it's visible from far away
## - Drops Marrow on death (night-gated Tether ingredient)
## - Does not flee campfires — light repel is a tier-1 behaviour only
## - Spawns in Tangle (tier-2 Bloom) and Mire (tier-3 Bloom) at night
extends "res://world/mobs/Mob.gd"

const NightDarknessScript := preload("res://world/NightDarkness.gd")

const WISP_HP          := 22
const WISP_CHASE_SPEED := 95.0

## Bioluminescent glow palette — vivid teal-green.
const COLOR_GLOW   := Color(0.15, 0.90, 0.55)
const COLOR_GLOW_2 := Color(0.10, 0.75, 0.45)
const COLOR_DIM    := Color(0.05, 0.45, 0.28, 0.6)

## Petal shape (similar to Sprout but more elongated).
const PETAL_COUNT := 5
const INNER_R     := 3.0
const OUTER_R     := 7.0

var _light: PointLight2D = null
var _pulse_t: float = 0.0  # drives glow pulse animation

## Bloom mob — reveal flash shows Still crystalline blue.
func _reveal_color() -> Color:
	return Color(0.60, 0.80, 0.98)

func _ready() -> void:
	super._ready()
	var h := get_node_or_null("Health")
	if h != null:
		h.max_hp = WISP_HP
		h.current_hp = WISP_HP
	_attach_light()

func _attach_light() -> void:
	_light = PointLight2D.new()
	_light.energy = 0.9
	_light.color = COLOR_GLOW
	_light.texture = NightDarknessScript._make_radial_texture(64)
	_light.texture_scale = 1.0
	_light.shadow_enabled = false
	add_child(_light)

func _process(delta: float) -> void:
	super._process(delta)
	_pulse_t += delta * 2.2
	if _light != null:
		_light.energy = 0.75 + sin(_pulse_t) * 0.2

func _draw() -> void:
	var base_color: Color
	if _reveal_timer > 0.0:
		var t: float = _reveal_timer / REVEAL_DURATION
		base_color = _reveal_color().lerp(COLOR_DIM, 1.0 - t)
	elif _state == State.DEAD:
		base_color = COLOR_DIM
	elif _flash_timer > 0.0:
		base_color = Color(0.9, 1.0, 0.7)
	else:
		base_color = COLOR_GLOW.lerp(COLOR_GLOW_2, abs(sin(_pulse_t * 0.5)))

	var pts := PackedVector2Array()
	for i in range(PETAL_COUNT * 2):
		var angle := (float(i) / float(PETAL_COUNT * 2)) * TAU
		var r: float = OUTER_R if (i % 2 == 0) else INNER_R
		pts.append(Vector2(cos(angle) * r, sin(angle) * r))

	var outline := PackedVector2Array()
	for pt in pts:
		outline.append(pt * 1.3)
	draw_colored_polygon(outline, Color(0.02, 0.15, 0.08))
	draw_colored_polygon(pts, base_color)

	if _state != State.DEAD:
		var health_node := get_node_or_null("Health")
		if health_node != null:
			var hp_frac: float = float(health_node.current_hp) / float(health_node.max_hp)
			draw_rect(Rect2(-8.0, -(OUTER_R + 7.0), 16.0, 3.0), Color(0.2, 0.2, 0.2, 0.8))
			var fill_color := Color(0.2, 0.85, 0.2).lerp(Color(0.9, 0.1, 0.1), 1.0 - hp_frac)
			draw_rect(Rect2(-8.0, -(OUTER_R + 7.0), 16.0 * hp_frac, 3.0), fill_color)

func _tick_chase(_delta: float) -> void:
	if player == null:
		_state = State.IDLE
		_idle_timer = 1.0
		return
	var dist := _dist_to_player_tiles()
	if dist > LOSE_RADIUS:
		_state = State.IDLE
		_idle_timer = randf_range(1.0, 2.0)
		return
	var dir: Vector2 = player.position - position
	if dir.length() > 0.1:
		dir = dir.normalized()
		_facing = dir
		velocity = dir * WISP_CHASE_SPEED
		move_and_slide()
	if dist <= ATTACK_RANGE and _attack_cooldown <= 0.0:
		_attack_cooldown = ATTACK_COOLDOWN
		if player.has_method("take_damage"):
			player.take_damage(ATTACK_DAMAGE)

func _on_death() -> void:
	if _light != null:
		_light.energy = 0.0
	emit_signal("mob_died", _tile_pos())
