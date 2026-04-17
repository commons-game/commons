## Mob — basic enemy with idle/patrol/chase/dead AI.
## chunk_manager and player must be set before the node enters the tree.
extends CharacterBody2D

signal mob_died(tile_pos: Vector2i)

const HealthScript := preload("res://world/mobs/Health.gd")

const MOB_HP := 30
const PATROL_SPEED := 40.0
const CHASE_SPEED  := 60.0
const CHASE_RADIUS := 6.0    # tiles
const LOSE_RADIUS  := 10.0   # tiles — give up chase beyond this
const ATTACK_RANGE := 1.5    # tiles
const ATTACK_DAMAGE := 10
const ATTACK_COOLDOWN := 1.5  # seconds

## Filled circle radius (px).
const RADIUS := 6.0
const TRI_SIZE := 3.5

var chunk_manager = null  # ChunkManager — set by spawner
var player: Node = null   # Player node — set by spawner

enum State { IDLE, PATROL, CHASE, DEAD }
var _state: int = State.IDLE

var _idle_timer: float = 0.0
var _patrol_target: Vector2 = Vector2.ZERO
var _facing: Vector2 = Vector2.DOWN
var _attack_cooldown: float = 0.0
var _dead_timer: float = 0.0
var _flash_timer: float = 0.0

const FLASH_DURATION := 0.12

## Set by the attacker before dealing the killing blow — used for the reveal effect.
var last_damage_source: String = ""
## When > 0, draw the opposite-force reveal flash instead of normal color.
var _reveal_timer: float = 0.0
const REVEAL_DURATION := 0.6

func _ready() -> void:
	z_index = 2
	# Health child — already in scene tree via Mob.tscn, but also handle code-only init
	var h = get_node_or_null("Health")
	if h == null:
		h = HealthScript.new()
		h.name = "Health"
		add_child(h)
	# Set HP directly — calling _init on a node that's already been constructed
	# causes "Too many arguments" parse errors when done from scene tree context.
	h.max_hp = MOB_HP
	h.current_hp = MOB_HP
	h.died.connect(_on_health_died)
	h.damaged.connect(func(_amount, _current, _maximum): _flash_timer = FLASH_DURATION)
	_idle_timer = randf_range(1.0, 2.0)

## Returns the reveal-flash color for this mob's opposite force.
## Override in subclasses: Bloom mobs return Still color, Still mobs return Bloom color.
func _reveal_color() -> Color:
	return Color(0.55, 0.72, 0.92)  # default: pale Still blue

func _draw() -> void:
	# Dark red filled circle + direction triangle (smaller than player).
	var base_color := Color(0.55, 0.05, 0.05)
	if _reveal_timer > 0.0:
		var t: float = _reveal_timer / REVEAL_DURATION
		base_color = _reveal_color().lerp(Color(0.55, 0.05, 0.05), 1.0 - t)
	elif _state == State.DEAD:
		base_color = Color(0.3, 0.05, 0.05, 0.5)
	elif _flash_timer > 0.0:
		base_color = Color(1.0, 0.6, 0.4)
	draw_circle(Vector2.ZERO, RADIUS, Color(0.15, 0.0, 0.0))   # outline
	draw_circle(Vector2.ZERO, RADIUS - 1.0, base_color)
	# Direction triangle
	var tip   := _facing * (RADIUS + TRI_SIZE)
	var left  := _facing.rotated(deg_to_rad( 140.0)) * (TRI_SIZE * 0.8)
	var right := _facing.rotated(deg_to_rad(-140.0)) * (TRI_SIZE * 0.8)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.9, 0.3, 0.1))
	# HP bar (skip when dead or no health node)
	if _state != State.DEAD:
		var health_node = get_node_or_null("Health")
		if health_node != null:
			var hp_frac: float = float(health_node.current_hp) / float(health_node.max_hp)
			var bar_x := -8.0
			var bar_y := -(RADIUS + 7.0)
			# Background
			draw_rect(Rect2(bar_x, bar_y, 16.0, 3.0), Color(0.2, 0.2, 0.2, 0.8))
			# Fill — lerp green to red
			var fill_color := Color(0.2, 0.85, 0.2).lerp(Color(0.9, 0.1, 0.1), 1.0 - hp_frac)
			draw_rect(Rect2(bar_x, bar_y, 16.0 * hp_frac, 3.0), fill_color)

func _process(_delta: float) -> void:
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
	if _reveal_timer > 0.0:
		_reveal_timer = maxf(_reveal_timer - delta, 0.0)

	if _state == State.DEAD:
		_dead_timer += delta
		modulate.a = 1.0 - (_dead_timer / 0.5)
		if _dead_timer >= 0.5:
			queue_free()
		return

	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	match _state:
		State.IDLE:
			_tick_idle(delta)
		State.PATROL:
			_tick_patrol(delta)
		State.CHASE:
			_tick_chase(delta)

func _tile_pos() -> Vector2i:
	return Vector2i(int(floorf(position.x / Constants.TILE_SIZE)),
	                int(floorf(position.y / Constants.TILE_SIZE)))

func _player_tile() -> Vector2i:
	if player == null:
		return Vector2i(99999, 99999)
	return Vector2i(int(floorf(player.position.x / Constants.TILE_SIZE)),
	                int(floorf(player.position.y / Constants.TILE_SIZE)))

func _dist_to_player_tiles() -> float:
	return (_player_tile() - _tile_pos()).length()

func _tick_idle(delta: float) -> void:
	velocity = Vector2.ZERO
	_idle_timer -= delta
	# Check if player is close enough to chase
	if player != null and _dist_to_player_tiles() <= CHASE_RADIUS:
		_state = State.CHASE
		return
	if _idle_timer <= 0.0:
		# Pick a random nearby tile as patrol target
		var rng := RandomNumberGenerator.new()
		rng.seed = int(position.x * 31337 + position.y * 99991 + Time.get_ticks_msec())
		var offset := Vector2(rng.randi_range(-5, 5), rng.randi_range(-5, 5))
		_patrol_target = position + offset * Constants.TILE_SIZE
		_state = State.PATROL

func _tick_patrol(_delta: float) -> void:
	# Check if player is close enough to chase
	if player != null and _dist_to_player_tiles() <= CHASE_RADIUS:
		_state = State.CHASE
		return

	var dir: Vector2 = _patrol_target - position
	if dir.length() < 4.0:
		# Reached patrol target, go idle
		velocity = Vector2.ZERO
		_idle_timer = randf_range(1.0, 2.0)
		_state = State.IDLE
		return

	dir = dir.normalized()
	_facing = dir
	velocity = dir * PATROL_SPEED
	move_and_slide()

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

	# Move toward player
	var dir: Vector2 = player.position - position
	if dir.length() > 0.1:
		dir = dir.normalized()
		_facing = dir
		velocity = dir * CHASE_SPEED
		move_and_slide()

	# Attack if adjacent
	if dist <= ATTACK_RANGE and _attack_cooldown <= 0.0:
		_attack_cooldown = ATTACK_COOLDOWN
		if player.has_method("take_damage"):
			player.take_damage(ATTACK_DAMAGE)

func _on_health_died() -> void:
	_state = State.DEAD
	velocity = Vector2.ZERO
	_dead_timer = 0.0
	if last_damage_source == "flint_knife":
		_reveal_timer = REVEAL_DURATION
	_on_death()

func _on_death() -> void:
	emit_signal("mob_died", _tile_pos())
