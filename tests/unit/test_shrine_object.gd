## Tests for ShrineObject — the in-world anchor that registers a shrine with ShrineTerritory.
## Rules:
##   - Calling initialize() registers the shrine's chunk with ShrineTerritory.
##   - Calling remove() unregisters the shrine, dissolving its territory.
##   - ShrineObject stores shrine_id, chunk_coords, mod_bundle_hash,
##     mod_bundle_version, and owner_id.
extends GdUnitTestSuite

const ShrineObjectScript    := preload("res://mods/ShrineObject.gd")
const ShrineTerritoryScript := preload("res://mods/ShrineTerritory.gd")

func _make_territory() -> Object:
	return ShrineTerritoryScript.new()

func _make_shrine(shrine_id: String, coords: Vector2i, territory: Object) -> Object:
	var s = ShrineObjectScript.new()
	s.initialize(shrine_id, coords, territory)
	return s

# --- initialize registers with territory ---

func test_initialize_registers_chunk() -> void:
	var t = _make_territory()
	_make_shrine("shrine_A", Vector2i(0, 0), t)
	assert_that(t.get_shrine_for_chunk(Vector2i(0, 0))).is_equal("shrine_A")

func test_initialize_stores_shrine_id() -> void:
	var t = _make_territory()
	var s = _make_shrine("shrine_A", Vector2i(0, 0), t)
	assert_that(s.shrine_id).is_equal("shrine_A")

func test_initialize_stores_chunk_coords() -> void:
	var t = _make_territory()
	var s = _make_shrine("shrine_A", Vector2i(3, 7), t)
	assert_that(s.chunk_coords).is_equal(Vector2i(3, 7))

# --- metadata fields ---

func test_mod_bundle_hash_stored() -> void:
	var t = _make_territory()
	var s = ShrineObjectScript.new()
	s.mod_bundle_hash = "abc123"
	s.initialize("shrine_A", Vector2i(0, 0), t)
	assert_that(s.mod_bundle_hash).is_equal("abc123")

func test_owner_id_stored() -> void:
	var t = _make_territory()
	var s = ShrineObjectScript.new()
	s.owner_id = "player_1"
	s.initialize("shrine_A", Vector2i(0, 0), t)
	assert_that(s.owner_id).is_equal("player_1")

func test_mod_bundle_version_stored() -> void:
	var t = _make_territory()
	var s = ShrineObjectScript.new()
	s.mod_bundle_version = "v1.0.0"
	s.initialize("shrine_A", Vector2i(0, 0), t)
	assert_that(s.mod_bundle_version).is_equal("v1.0.0")

# --- remove dissolves territory ---

func test_remove_unregisters_chunk() -> void:
	var t = _make_territory()
	var s = _make_shrine("shrine_A", Vector2i(0, 0), t)
	s.remove(t)
	assert_that(t.get_shrine_for_chunk(Vector2i(0, 0))).is_null()

func test_remove_dissolves_expanded_territory() -> void:
	var t = _make_territory()
	var s = _make_shrine("shrine_A", Vector2i(0, 0), t)
	t.on_chunk_modified(Vector2i(1, 0))
	s.remove(t)
	assert_that(t.get_shrine_for_chunk(Vector2i(1, 0))).is_null()

# --- Two shrines coexist ---

func test_two_shrines_coexist_independently() -> void:
	var t = _make_territory()
	_make_shrine("shrine_A", Vector2i(0, 0), t)
	_make_shrine("shrine_B", Vector2i(10, 0), t)
	assert_that(t.get_shrine_for_chunk(Vector2i(0, 0))).is_equal("shrine_A")
	assert_that(t.get_shrine_for_chunk(Vector2i(10, 0))).is_equal("shrine_B")
