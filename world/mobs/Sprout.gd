## Sprout — tier-1 Bloom-force mob. "Something small that used to be an animal,
## beginning to change."
##
## Differences from base Mob:
##   - 20 HP (vs 30)
##   - CHASE_SPEED 70.0 (vs 60.0) — slightly faster at night when the Bloom stirs
##   - Drawn as a small irregular greenish organic shape (not the red circle)
##   - Drops Pulp on death ("pulp_drop" marker) instead of generic mob loot
##   - Supports flee() call: moves away from player for `_flee_timer` seconds then frees
extends "res://world/mobs/Mob.gd"

## Override base constants.
const SPROUT_HP         := 20
const SPROUT_CHASE_SPEED := 70.0

## Organic shape: a small ring of irregular points around origin.
const PETAL_COUNT := 6
const INNER_R     := 3.5
const OUTER_R     := 6.5

## Flee state — triggered by NightSpawner on dawn.
var _fleeing: bool = false
var _flee_timer: float = 0.0
const FLEE_DURATION := 2.0
const FLEE_SPEED    := 90.0

func _ready() -> void:
	super._ready()
	# Override HP from base.
	var h := get_node_or_null("Health")
	if h != null:
		h.max_hp = SPROUT_HP
		h.current_hp = SPROUT_HP

func _draw() -> void:
	# Bloom palette: yellow-green tones with slight variation.
	var base_color: Color
	if _state == State.DEAD:
		base_color = Color(0.15, 0.35, 0.08, 0.5)
	elif _flash_timer > 0.0:
		base_color = Color(0.9, 1.0, 0.5)
	elif _fleeing:
		base_color = Color(0.55, 0.75, 0.15)
	else:
		base_color = Color(0.22, 0.62, 0.08)

	# Build irregular polygon — alternating inner/outer radius with slight angular jitter.
	var pts := PackedVector2Array()
	for i in range(PETAL_COUNT * 2):
		var angle := (float(i) / float(PETAL_COUNT * 2)) * TAU
		# Alternate between outer spike and inner indent.
		var r: float = OUTER_R if (i % 2 == 0) else INNER_R
		pts.append(Vector2(cos(angle) * r, sin(angle) * r))

	# Dark outline (slightly larger version in near-black green).
	var outline := PackedVector2Array()
	for pt in pts:
		outline.append(pt * 1.25)
	draw_colored_polygon(outline, Color(0.04, 0.12, 0.02))
	draw_colored_polygon(pts, base_color)

	# Direction nub — small darker teardrop in facing direction.
	var nub_tip   := _facing * (OUTER_R + 2.5)
	var nub_left  := _facing.rotated(deg_to_rad( 150.0)) * 2.0
	var nub_right := _facing.rotated(deg_to_rad(-150.0)) * 2.0
	draw_colored_polygon(PackedVector2Array([nub_tip, nub_left, nub_right]),
	                     Color(0.55, 0.85, 0.1))

	# HP bar (same pattern as base Mob).
	if _state != State.DEAD:
		var health_node := get_node_or_null("Health")
		if health_node != null:
			var hp_frac: float = float(health_node.current_hp) / float(health_node.max_hp)
			var bar_x := -8.0
			var bar_y := -(OUTER_R + 7.0)
			draw_rect(Rect2(bar_x, bar_y, 16.0, 3.0), Color(0.2, 0.2, 0.2, 0.8))
			var fill_color := Color(0.2, 0.85, 0.2).lerp(Color(0.9, 0.1, 0.1), 1.0 - hp_frac)
			draw_rect(Rect2(bar_x, bar_y, 16.0 * hp_frac, 3.0), fill_color)

func _physics_process(delta: float) -> void:
	if _fleeing and _state != State.DEAD:
		_tick_flee(delta)
		return
	super._physics_process(delta)

func _tick_chase(_delta: float) -> void:
	# Use Sprout's faster chase speed by temporarily shadowing the base constant.
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
		# Steer away from campfires if one is too close.
		var my_tile := Vector2i(int(floorf(position.x / Constants.TILE_SIZE)),
		                        int(floorf(position.y / Constants.TILE_SIZE)))
		var nearest_cf: Vector2i = CampfireRegistry.nearest_campfire_tile(my_tile)
		const AVOID_RADIUS := 6  # tiles (LIGHT_RADIUS * 0.8 rounded)
		if nearest_cf != Vector2i(-9999, -9999):
			var cf_dist: float = (nearest_cf - my_tile).length()
			if cf_dist < AVOID_RADIUS:
				var cf_world_pos := Vector2(
					nearest_cf.x * Constants.TILE_SIZE + Constants.TILE_SIZE * 0.5,
					nearest_cf.y * Constants.TILE_SIZE + Constants.TILE_SIZE * 0.5)
				var away: Vector2 = (position - cf_world_pos).normalized()
				# Blend away vector with chase direction — tangential orbit.
				var blend: float = 1.0 - (cf_dist / AVOID_RADIUS)
				dir = (dir + away * blend * 2.0).normalized()
		_facing = dir
		velocity = dir * SPROUT_CHASE_SPEED
		move_and_slide()

	if dist <= ATTACK_RANGE and _attack_cooldown <= 0.0:
		_attack_cooldown = ATTACK_COOLDOWN
		if player.has_method("take_damage"):
			player.take_damage(ATTACK_DAMAGE)

## Called by NightSpawner on dawn transition for Sprouts not in active chase.
func flee() -> void:
	if _state == State.DEAD:
		return
	_fleeing = true
	_flee_timer = FLEE_DURATION

func _tick_flee(delta: float) -> void:
	_flee_timer -= delta
	if _flee_timer <= 0.0:
		queue_free()
		return
	# Run away from player (or a fixed direction if no player).
	var dir: Vector2
	if player != null:
		dir = (position - player.position).normalized()
	else:
		dir = Vector2(1.0, 0.0)
	_facing = dir
	velocity = dir * FLEE_SPEED
	move_and_slide()

func _on_death() -> void:
	# Emit with tile position for NightSpawner tracking, then drop Pulp.
	emit_signal("mob_died", _tile_pos())
