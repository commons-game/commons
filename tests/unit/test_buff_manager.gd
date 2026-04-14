## Tests for BuffManager — tracks active buffs and evicts them on shrine boundary crossing.
## Rules:
##   - add_buff() stores the buff with its origin_shrine.
##   - get_buffs() returns all currently active buffs.
##   - on_chunk_changed(new_chunk) removes buffs whose origin_shrine doesn't match
##     the shrine owning new_chunk.
##   - Buffs with origin_shrine == "" (origin-less) are never evicted.
extends GdUnitTestSuite

const BuffManagerScript     := preload("res://mods/BuffManager.gd")
const ShrineTerritoryScript := preload("res://mods/ShrineTerritory.gd")

func _make_territory() -> Object:
	var t = ShrineTerritoryScript.new()
	t.register_shrine("shrine_A", Vector2i(0, 0))
	t.register_shrine("shrine_B", Vector2i(10, 0))
	return t

func _make_manager(territory: Object) -> Object:
	var m = BuffManagerScript.new()
	m.territory = territory
	return m

# --- add and get ---

func test_add_buff_visible_in_get_buffs() -> void:
	var m = _make_manager(_make_territory())
	m.add_buff("speed_up", "shrine_A")
	assert_that(m.get_buffs().size()).is_equal(1)

func test_get_buffs_returns_empty_initially() -> void:
	var m = _make_manager(_make_territory())
	assert_that(m.get_buffs().size()).is_equal(0)

func test_multiple_buffs_stored() -> void:
	var m = _make_manager(_make_territory())
	m.add_buff("speed_up", "shrine_A")
	m.add_buff("shield", "shrine_A")
	assert_that(m.get_buffs().size()).is_equal(2)

# --- on_chunk_changed eviction ---

func test_buffs_retained_when_still_in_origin_shrine() -> void:
	var m = _make_manager(_make_territory())
	m.add_buff("speed_up", "shrine_A")
	m.on_chunk_changed(Vector2i(0, 0))   # shrine_A owns (0,0)
	assert_that(m.get_buffs().size()).is_equal(1)

func test_buffs_evicted_when_leaving_origin_shrine() -> void:
	var m = _make_manager(_make_territory())
	m.add_buff("speed_up", "shrine_A")
	m.on_chunk_changed(Vector2i(10, 0))  # shrine_B's chunk
	assert_that(m.get_buffs().size()).is_equal(0)

func test_buffs_evicted_when_entering_wilderness() -> void:
	var m = _make_manager(_make_territory())
	m.add_buff("speed_up", "shrine_A")
	m.on_chunk_changed(Vector2i(99, 99))  # wilderness
	assert_that(m.get_buffs().size()).is_equal(0)

func test_mixed_buffs_only_evict_wrong_shrine() -> void:
	var m = _make_manager(_make_territory())
	m.add_buff("shrine_a_buff", "shrine_A")
	m.add_buff("shrine_b_buff", "shrine_B")
	m.on_chunk_changed(Vector2i(0, 0))  # shrine_A
	var remaining: Array = m.get_buffs()
	assert_that(remaining.size()).is_equal(1)
	assert_that(remaining[0].buff_id).is_equal("shrine_a_buff")

# --- Origin-less buffs never evicted ---

func test_originless_buff_survives_shrine_change() -> void:
	var m = _make_manager(_make_territory())
	m.add_buff("natural_regen", "")   # no shrine origin
	m.on_chunk_changed(Vector2i(99, 99))  # wilderness
	assert_that(m.get_buffs().size()).is_equal(1)

# --- get_buffs returns buff_id values ---

func test_get_buffs_entries_have_buff_id() -> void:
	var m = _make_manager(_make_territory())
	m.add_buff("fire_resist", "shrine_A")
	var buffs: Array = m.get_buffs()
	assert_that(buffs[0].buff_id).is_equal("fire_resist")
