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
	_idle_timer = randf_range(1.0, 2.0)

func _draw() -> void:
	# Dark red filled circle + direction triangle (smaller than player).
	var base_color := Color(0.55, 0.05, 0.05)
	if _state == State.DEAD:
		base_color = Color(0.3, 0.05, 0.05, 0.5)
	draw_circle(Vector2.ZERO, RADIUS, Color(0.15, 0.0, 0.0))   # outline
	draw_circle(Vector2.ZERO, RADIUS - 1.0, base_color)
	# Direction triangle
	var tip   := _facing * (RADIUS + TRI_SIZE)
	var left  := _facing.rotated(deg_to_rad( 140.0)) * (TRI_SIZE * 0.8)
	var right := _facing.rotated(deg_to_rad(-140.0)) * (TRI_SIZE * 0.8)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.9, 0.3, 0.1))

func _process(_delta: float) -> void:
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		_dead_timer += delta
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

func _tick_patrol(delta: float) -> void:
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
	_on_death()

func _on_death() -> void:
	emit_signal("mob_died", _tile_pos())
