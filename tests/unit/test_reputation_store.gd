## Tests for ReputationStore — in-memory report and chaos-pool state.
##
## Rules:
##   - submit_report() records a report against target_id.
##   - get_report_count() returns how many reports a player has received.
##   - A player can only submit one report against a given target (spam prevention).
##   - Self-reports are silently ignored.
##   - When report_count reaches REPORT_THRESHOLD the player is auto-promoted
##     to the chaos pool.
##   - opt_into_chaos_pool() voluntarily promotes a player (regardless of count).
##   - is_in_chaos_pool() reflects both auto and voluntary promotion.
##   - get_reputation_flags() returns { report_count, in_chaos_pool }.
extends GdUnitTestSuite

const ReputationStoreScript := preload("res://reputation/ReputationStore.gd")

func _make_store() -> Object:
	return ReputationStoreScript.new()

# --- Report submission ---

func test_new_player_has_zero_reports() -> void:
	var s = _make_store()
	assert_that(s.get_report_count("player_x")).is_equal(0)

func test_submit_report_increments_count() -> void:
	var s = _make_store()
	s.submit_report("reporter_1", "target_a", "griefing")
	assert_that(s.get_report_count("target_a")).is_equal(1)

func test_multiple_reporters_accumulate() -> void:
	var s = _make_store()
	s.submit_report("reporter_1", "target_a", "griefing")
	s.submit_report("reporter_2", "target_a", "spam")
	assert_that(s.get_report_count("target_a")).is_equal(2)

func test_same_reporter_cannot_report_twice() -> void:
	var s = _make_store()
	s.submit_report("reporter_1", "target_a", "griefing")
	s.submit_report("reporter_1", "target_a", "griefing again")
	assert_that(s.get_report_count("target_a")).is_equal(1)

func test_self_report_is_ignored() -> void:
	var s = _make_store()
	s.submit_report("player_x", "player_x", "i hate myself")
	assert_that(s.get_report_count("player_x")).is_equal(0)

func test_reports_against_different_targets_are_independent() -> void:
	var s = _make_store()
	s.submit_report("reporter_1", "target_a", "bad")
	s.submit_report("reporter_1", "target_b", "also bad")
	assert_that(s.get_report_count("target_a")).is_equal(1)
	assert_that(s.get_report_count("target_b")).is_equal(1)

# --- Auto-promotion to chaos pool ---

func test_below_threshold_not_in_chaos_pool() -> void:
	var s = _make_store()
	s.submit_report("r1", "target_a", "x")
	assert_bool(s.is_in_chaos_pool("target_a")).is_false()

func test_reaching_threshold_promotes_to_chaos_pool() -> void:
	var s = _make_store()
	for i in range(s.REPORT_THRESHOLD):
		s.submit_report("reporter_%d" % i, "target_a", "x")
	assert_bool(s.is_in_chaos_pool("target_a")).is_true()

func test_unknown_player_not_in_chaos_pool() -> void:
	var s = _make_store()
	assert_bool(s.is_in_chaos_pool("ghost")).is_false()

# --- Voluntary chaos pool opt-in ---

func test_opt_in_sets_chaos_pool_flag() -> void:
	var s = _make_store()
	s.opt_into_chaos_pool("player_pvp")
	assert_bool(s.is_in_chaos_pool("player_pvp")).is_true()

func test_opt_in_independent_of_report_count() -> void:
	var s = _make_store()
	s.opt_into_chaos_pool("clean_player")
	assert_that(s.get_report_count("clean_player")).is_equal(0)
	assert_bool(s.is_in_chaos_pool("clean_player")).is_true()

# --- get_reputation_flags ---

func test_flags_reflect_report_count() -> void:
	var s = _make_store()
	s.submit_report("r1", "target_a", "x")
	var flags: Dictionary = s.get_reputation_flags("target_a") as Dictionary
	assert_that(int(flags["report_count"])).is_equal(1)

func test_flags_reflect_chaos_pool_status() -> void:
	var s = _make_store()
	s.opt_into_chaos_pool("player_x")
	var flags: Dictionary = s.get_reputation_flags("player_x") as Dictionary
	assert_bool(flags["in_chaos_pool"]).is_true()

func test_flags_for_unknown_player_are_clean() -> void:
	var s = _make_store()
	var flags: Dictionary = s.get_reputation_flags("nobody") as Dictionary
	assert_that(int(flags["report_count"])).is_equal(0)
	assert_bool(flags["in_chaos_pool"]).is_false()
