## Tests for BoundaryEnforcer — vampire rule for entities outside their origin shrine.
## Rules:
##   - Entity in a chunk owned by its origin_shrine → safe, no action.
##   - Entity in a chunk owned by a different shrine, contested, or wilderness → damaged.
##   - Entity health ≤ 0 after damage → die_at_boundary() called.
extends GdUnitTestSuite

const BoundaryEnforcerScript := preload("res://mods/BoundaryEnforcer.gd")
const ShrineTerritoryScript  := preload("res://mods/ShrineTerritory.gd")

# Minimal mock entity with the interface BoundaryEnforcer expects.
class MockEntity:
	var origin_shrine: String = ""
	var health: float = 100.0
	var damage_taken: float = 0.0
	var boundary_death_called: bool = false

	func apply_boundary_damage(amount: float) -> void:
		damage_taken += amount
		health -= amount

	func die_at_boundary() -> void:
		boundary_death_called = true

func _make_territory() -> Object:
	var t = ShrineTerritoryScript.new()
	t.register_shrine("shrine_A", Vector2i(0, 0))
	t.register_shrine("shrine_B", Vector2i(5, 0))
	return t

func _make_enforcer(territory: Object) -> Object:
	var e = BoundaryEnforcerScript.new()
	e.territory = territory
	e.damage_per_tick = 10.0
	return e

# --- Entity in its own shrine territory ---

func test_entity_safe_in_own_shrine_chunk() -> void:
	var t = _make_territory()
	var e = _make_enforcer(t)
	var entity = MockEntity.new()
	entity.origin_shrine = "shrine_A"
	e.on_entity_moved(entity, Vector2i(0, 0), 0.016)
	assert_that(entity.damage_taken).is_equal(0.0)

# --- Entity outside its shrine ---

func test_entity_damaged_in_wilderness() -> void:
	var t = _make_territory()
	var e = _make_enforcer(t)
	var entity = MockEntity.new()
	entity.origin_shrine = "shrine_A"
	# (99,99) is wilderness
	e.on_entity_moved(entity, Vector2i(99, 99), 0.016)
	assert_that(entity.damage_taken).is_greater(0.0)

func test_entity_damaged_in_foreign_shrine() -> void:
	var t = _make_territory()
	var e = _make_enforcer(t)
	var entity = MockEntity.new()
	entity.origin_shrine = "shrine_A"
	# shrine_B's home chunk
	e.on_entity_moved(entity, Vector2i(5, 0), 0.016)
	assert_that(entity.damage_taken).is_greater(0.0)

func test_entity_damaged_in_contested_chunk() -> void:
	var t = _make_territory()
	# Make (1,0) adjacent to shrine_A (0,0) and simulate shrine_B at (2,0)
	var t2 = ShrineTerritoryScript.new()
	t2.register_shrine("shrine_A", Vector2i(0, 0))
	t2.register_shrine("shrine_B", Vector2i(2, 0))
	t2.on_chunk_modified(Vector2i(1, 0))  # contested
	var e = _make_enforcer(t2)
	var entity = MockEntity.new()
	entity.origin_shrine = "shrine_A"
	e.on_entity_moved(entity, Vector2i(1, 0), 0.016)
	assert_that(entity.damage_taken).is_greater(0.0)

# --- Damage scales with delta ---

func test_damage_scales_with_delta() -> void:
	var t = _make_territory()
	var e = _make_enforcer(t)
	var entity = MockEntity.new()
	entity.origin_shrine = "shrine_A"
	e.on_entity_moved(entity, Vector2i(99, 99), 1.0)  # delta=1s
	assert_that(entity.damage_taken).is_equal(10.0)  # damage_per_tick * delta

# --- Death at boundary ---

func test_entity_dies_when_health_reaches_zero() -> void:
	var t = _make_territory()
	var e = _make_enforcer(t)
	var entity = MockEntity.new()
	entity.origin_shrine = "shrine_A"
	entity.health = 5.0
	e.damage_per_tick = 100.0
	e.on_entity_moved(entity, Vector2i(99, 99), 1.0)
	assert_bool(entity.boundary_death_called).is_true()

func test_entity_does_not_die_with_health_remaining() -> void:
	var t = _make_territory()
	var e = _make_enforcer(t)
	var entity = MockEntity.new()
	entity.origin_shrine = "shrine_A"
	entity.health = 200.0
	e.on_entity_moved(entity, Vector2i(99, 99), 1.0)
	assert_bool(entity.boundary_death_called).is_false()

# --- Entity with no origin shrine is always safe (player / neutral) ---

func test_entity_with_empty_origin_shrine_not_damaged() -> void:
	var t = _make_territory()
	var e = _make_enforcer(t)
	var entity = MockEntity.new()
	entity.origin_shrine = ""  # no shrine affiliation
	e.on_entity_moved(entity, Vector2i(99, 99), 1.0)
	assert_that(entity.damage_taken).is_equal(0.0)
