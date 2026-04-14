## Tests for TalismanOfChaos — item that opts a player into the chaos merge pool.
##
## Rules:
##   - apply_to(player_id, store) calls store.opt_into_chaos_pool(player_id).
##   - After applying, is_in_chaos_pool() returns true.
##   - Applying to a player already in the chaos pool is idempotent.
##   - The talisman does not modify merge pressure (that's TalismanItem's job).
extends GdUnitTestSuite

const TalismanOfChaosScript := preload("res://reputation/TalismanOfChaos.gd")
const ReputationStoreScript := preload("res://reputation/ReputationStore.gd")

func _make_store() -> Object:
	return ReputationStoreScript.new()

func _make_talisman() -> Object:
	return TalismanOfChaosScript.new()

func test_apply_opts_player_into_chaos_pool() -> void:
	var store = _make_store()
	var talisman = _make_talisman()
	talisman.apply_to("player_x", store)
	assert_bool(store.is_in_chaos_pool("player_x")).is_true()

func test_apply_does_not_affect_other_players() -> void:
	var store = _make_store()
	var talisman = _make_talisman()
	talisman.apply_to("player_x", store)
	assert_bool(store.is_in_chaos_pool("player_y")).is_false()

func test_apply_idempotent_when_already_in_chaos_pool() -> void:
	var store = _make_store()
	var talisman = _make_talisman()
	talisman.apply_to("player_x", store)
	talisman.apply_to("player_x", store)  # should not crash or double-flag
	assert_bool(store.is_in_chaos_pool("player_x")).is_true()
	assert_that(store.get_report_count("player_x")).is_equal(0)

func test_talisman_has_expected_id() -> void:
	var talisman = _make_talisman()
	assert_that(talisman.id).is_equal("talisman_of_chaos")
