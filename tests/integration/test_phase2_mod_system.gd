## Phase 2 end-to-end integration test.
## Exercises the full chain:
##   ShrineObject placed → territory registered
##   → adjacent chunk modified → territory expands
##   → BoundaryEnforcer detects entity outside shrine
##   → BuffManager evicts buff on chunk change
##   → ShrineObject removed → territory dissolved
extends GdUnitTestSuite

const ShrineObjectScript     := preload("res://mods/ShrineObject.gd")
const ShrineTerritoryScript  := preload("res://mods/ShrineTerritory.gd")
const BoundaryEnforcerScript := preload("res://mods/BoundaryEnforcer.gd")
const BuffManagerScript      := preload("res://mods/BuffManager.gd")
const ModBundleScript        := preload("res://mods/ModBundle.gd")
const ModRuntimeScript       := preload("res://mods/ModRuntime.gd")

# Minimal mock entity matching BoundaryEnforcer's expected interface.
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

func test_full_shrine_lifecycle() -> void:
	# --- Setup ---
	var territory  = ShrineTerritoryScript.new()
	var enforcer   = BoundaryEnforcerScript.new()
	var buff_mgr   = BuffManagerScript.new()
	enforcer.territory  = territory
	enforcer.damage_per_tick = 20.0
	buff_mgr.territory  = territory

	# 1. Place a shrine at chunk (0,0).
	var shrine = ShrineObjectScript.new()
	shrine.owner_id = "player_1"
	shrine.mod_bundle_hash = "deadbeef"
	shrine.initialize("shrine_A", Vector2i(0, 0), territory)

	assert_that(territory.get_shrine_for_chunk(Vector2i(0, 0))).is_equal("shrine_A")

	# 2. Player modifies adjacent chunk — territory expands.
	territory.on_chunk_modified(Vector2i(1, 0))
	assert_that(territory.get_shrine_for_chunk(Vector2i(1, 0))).is_equal("shrine_A")

	# 3. Shrine-bound entity enters shrine territory — safe.
	var entity = MockEntity.new()
	entity.origin_shrine = "shrine_A"
	enforcer.on_entity_moved(entity, Vector2i(0, 0), 1.0)
	assert_that(entity.damage_taken).is_equal(0.0)

	# 4. Entity leaves shrine territory — takes damage.
	enforcer.on_entity_moved(entity, Vector2i(99, 99), 1.0)
	assert_that(entity.damage_taken).is_greater(0.0)

	# 5. Player picks up a shrine buff while inside shrine territory.
	buff_mgr.add_buff("shrine_haste", "shrine_A")
	buff_mgr.on_chunk_changed(Vector2i(0, 0))   # still inside — buff retained
	assert_that(buff_mgr.get_buffs().size()).is_equal(1)

	# 6. Player walks out — buff is evicted.
	buff_mgr.on_chunk_changed(Vector2i(99, 99))
	assert_that(buff_mgr.get_buffs().size()).is_equal(0)

	# 7. Remove the shrine — territory dissolves.
	shrine.remove(territory)
	assert_that(territory.get_shrine_for_chunk(Vector2i(0, 0))).is_null()
	assert_that(territory.get_shrine_for_chunk(Vector2i(1, 0))).is_null()

func test_mod_bundle_applies_effects_in_shrine_territory() -> void:
	# ModRuntime fires tile effects inside shrine territory.
	var territory = ShrineTerritoryScript.new()
	var shrine    = ShrineObjectScript.new()
	shrine.initialize("shrine_A", Vector2i(0, 0), territory)

	var bundle = ModBundleScript.new()
	bundle.load_from_json(JSON.stringify({
		"tiles": [{
			"id": "poison_floor",
			"on_walk": [{"effects": [{"type": "deal_damage", "amount": 5}]}]
		}],
		"entities": [], "items": [], "buffs": []
	}))

	var runtime = ModRuntimeScript.new()
	# Chunk (0,0) is shrine_A's territory — mod effects should fire.
	var active_mod_set = territory.get_active_mod_set(Vector2i(0, 0))
	assert_that(active_mod_set).is_equal("shrine_A")

	var effects: Array = runtime.get_effects("poison_floor", {"trigger": "on_walk", "entity_tags": []}, bundle)
	assert_that(effects.size()).is_equal(1)
	assert_that(effects[0].type).is_equal("deal_damage")

func test_contested_chunk_has_no_active_mod_set_and_entity_takes_damage() -> void:
	var territory = ShrineTerritoryScript.new()
	var enforcer  = BoundaryEnforcerScript.new()
	enforcer.territory      = territory
	enforcer.damage_per_tick = 10.0

	var _s1 = ShrineObjectScript.new()
	_s1.initialize("shrine_A", Vector2i(0, 0), territory)
	var _s2 = ShrineObjectScript.new()
	_s2.initialize("shrine_B", Vector2i(2, 0), territory)

	# (1,0) is adjacent to both — contested after modification.
	territory.on_chunk_modified(Vector2i(1, 0))
	assert_that(territory.get_shrine_for_chunk(Vector2i(1, 0))).is_equal("CONTESTED")
	assert_that(territory.get_active_mod_set(Vector2i(1, 0))).is_null()

	# shrine_A entity in contested chunk takes damage.
	var entity = MockEntity.new()
	entity.origin_shrine = "shrine_A"
	enforcer.on_entity_moved(entity, Vector2i(1, 0), 1.0)
	assert_that(entity.damage_taken).is_greater(0.0)
