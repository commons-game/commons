## Pale — tier-2/3 Still night mob. Nearly invisible, slow, hits hard.
##
## "You almost walk into it before you see it."
##
## - Slow (CHASE_SPEED 28) — gives you time to react if you're paying attention
## - High HP (70) — takes real commitment to kill
## - High damage (22 per hit) — punishes being caught
## - Nearly transparent visually — low alpha, near-background colour
## - Leaves Moonstone patches on the ground as it walks (night only)
## - Moonstone tiles are harvestable and dissolve at dawn
## - Spawns in Shard (tier-2 Still) and Hollow (tier-3 Still) at night
extends "res://world/mobs/Mob.gd"

const PALE_HP           := 70
const PALE_CHASE_SPEED  := 28.0
const PALE_ATTACK_DMG   := 22

## How often (seconds) to try placing a Moonstone tile while moving.
## Baseline — actual interval scales with moon fullness in _moonstone_interval().
const MOONSTONE_DROP_INTERVAL := 4.0
var _moonstone_timer: float = 0.0

## Baked-in moon scaling captured at spawn so a single Pale is internally consistent
## (HP and damage don't shift mid-night as the clock ticks).
## Pale HP range: 50 (new moon, fragile but swarms) → 100 (full moon, formidable).
## Damage range: 18 → 30.
var _moon_scale: float = 0.0  # 0..1; set in _ready

## The Moonstone tiles this Pale has placed — cleared at dawn.
var _moonstone_tiles: Array = []

## Still mob — reveal flash shows Bloom organic green.
func _reveal_color() -> Color:
	return Color(0.22, 0.82, 0.38)

func _ready() -> void:
	super._ready()
	_moon_scale = DayClock.moon_fullness()
	# HP scales 0.7x (new) → 1.4x (full). Damage scales 0.8x (new) → 1.4x (full).
	var hp_scaled: int = int(round(PALE_HP * lerp(0.7, 1.4, _moon_scale)))
	var h := get_node_or_null("Health")
	if h != null:
		h.max_hp = hp_scaled
		h.current_hp = hp_scaled
	DayClock.phase_changed.connect(_on_phase_changed)

## Effective attack damage after moon scaling. Called from _tick_chase.
func _scaled_attack_dmg() -> int:
	return int(round(PALE_ATTACK_DMG * lerp(0.8, 1.4, _moon_scale)))

## Moonstone drop interval scales inversely with fullness.
## New moon (Still is hungriest): 1.8s — lots of Moonstone.
## Full moon: 6.0s — rare.
func _moonstone_interval() -> float:
	return lerp(1.8, 6.0, _moon_scale)

func _draw() -> void:
	# Nearly invisible: very low alpha, cold grey-white.
	var base_color: Color
	if _reveal_timer > 0.0:
		var t: float = _reveal_timer / REVEAL_DURATION
		base_color = _reveal_color().lerp(Color(0.70, 0.76, 0.88, 0.28), 1.0 - t)
	elif _state == State.DEAD:
		base_color = Color(0.75, 0.80, 0.88, 0.15)
	elif _flash_timer > 0.0:
		base_color = Color(0.90, 0.92, 1.0, 0.85)
	else:
		base_color = Color(0.70, 0.76, 0.88, 0.28)  # barely there

	# Simple hexagonal shape — geometric, Still-aligned.
	var pts := PackedVector2Array()
	for i in range(6):
		var angle := (float(i) / 6.0) * TAU - PI / 6.0
		pts.append(Vector2(cos(angle) * RADIUS, sin(angle) * RADIUS))

	draw_colored_polygon(pts, base_color)
	# Faint crystalline outline.
	for i in range(pts.size()):
		draw_line(pts[i], pts[(i + 1) % pts.size()],
		          Color(0.80, 0.88, 1.0, 0.45), 1.0)

	if _state != State.DEAD:
		var health_node := get_node_or_null("Health")
		if health_node != null:
			var hp_frac: float = float(health_node.current_hp) / float(health_node.max_hp)
			draw_rect(Rect2(-8.0, -(RADIUS + 7.0), 16.0, 3.0), Color(0.2, 0.2, 0.2, 0.5))
			var fill_color := Color(0.6, 0.75, 1.0).lerp(Color(0.9, 0.1, 0.1), 1.0 - hp_frac)
			draw_rect(Rect2(-8.0, -(RADIUS + 7.0), 16.0 * hp_frac, 3.0), fill_color)

func _tick_chase(delta: float) -> void:
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
		velocity = dir * PALE_CHASE_SPEED
		move_and_slide()
		_try_drop_moonstone(delta)
	if dist <= ATTACK_RANGE and _attack_cooldown <= 0.0:
		_attack_cooldown = ATTACK_COOLDOWN
		if player.has_method("take_damage"):
			player.take_damage(_scaled_attack_dmg())

func _try_drop_moonstone(delta: float) -> void:
	if chunk_manager == null:
		return
	_moonstone_timer += delta
	if _moonstone_timer < _moonstone_interval():
		return
	_moonstone_timer = 0.0
	var tile := _tile_pos()
	# Only drop if no object tile already there.
	if not chunk_manager.has_tile_at(tile, 1):
		chunk_manager.place_tile(tile, 1, 0, Vector2i(2, 2), 0, "moonstone_patch")
		_moonstone_tiles.append(tile)

func _on_phase_changed(is_day: bool) -> void:
	# Dissolve all Moonstone patches at dawn.
	if is_day and chunk_manager != null:
		for tile in _moonstone_tiles:
			chunk_manager.remove_tile(tile, 1, "moonstone_dawn")
		_moonstone_tiles.clear()

func _on_death() -> void:
	emit_signal("mob_died", _tile_pos())
