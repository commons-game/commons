## Tests for MergeRouter — gates merge proposals on reputation state.
##
## Rules (no bans — only routing):
##   - Normal + Normal → can merge.
##   - Chaos + Chaos   → can merge.
##   - Normal + Chaos  → cannot merge (routes incompatible).
##   - Chaos + Normal  → cannot merge.
##   - Unknown players are treated as Normal (clean slate).
extends GdUnitTestSuite

const MergeRouterScript     := preload("res://reputation/MergeRouter.gd")
const ReputationStoreScript := preload("res://reputation/ReputationStore.gd")

func _make_store() -> Object:
	return ReputationStoreScript.new()

func _make_router() -> Object:
	return MergeRouterScript.new()

# --- Normal × Normal ---

func test_two_normal_players_can_merge() -> void:
	var store = _make_store()
	var router = _make_router()
	assert_bool(router.can_merge("alice", "bob", store)).is_true()

# --- Chaos × Chaos ---

func test_two_chaos_players_can_merge() -> void:
	var store = _make_store()
	store.opt_into_chaos_pool("alice")
	store.opt_into_chaos_pool("bob")
	var router = _make_router()
	assert_bool(router.can_merge("alice", "bob", store)).is_true()

# --- Mixed pools — incompatible ---

func test_normal_and_chaos_cannot_merge() -> void:
	var store = _make_store()
	store.opt_into_chaos_pool("bob")
	var router = _make_router()
	assert_bool(router.can_merge("alice", "bob", store)).is_false()

func test_chaos_and_normal_cannot_merge_commutative() -> void:
	var store = _make_store()
	store.opt_into_chaos_pool("alice")
	var router = _make_router()
	assert_bool(router.can_merge("alice", "bob", store)).is_false()

# --- Reported player auto-promoted, then blocked from normal merges ---

func test_highly_reported_player_blocked_from_normal_merge() -> void:
	var store = _make_store()
	for i in range(store.REPORT_THRESHOLD):
		store.submit_report("reporter_%d" % i, "griefer", "bad")
	var router = _make_router()
	# griefer is now in chaos pool; clean player is not
	assert_bool(router.can_merge("clean_player", "griefer", store)).is_false()

func test_highly_reported_player_can_merge_with_another_chaos_player() -> void:
	var store = _make_store()
	for i in range(store.REPORT_THRESHOLD):
		store.submit_report("reporter_%d" % i, "griefer", "bad")
	store.opt_into_chaos_pool("pvp_lover")
	var router = _make_router()
	assert_bool(router.can_merge("griefer", "pvp_lover", store)).is_true()

# --- Unknown players are Normal ---

func test_unknown_player_treated_as_normal() -> void:
	var store = _make_store()
	var router = _make_router()
	assert_bool(router.can_merge("ghost_a", "ghost_b", store)).is_true()

func test_unknown_chaos_player_incompatible_with_unknown_normal() -> void:
	var store = _make_store()
	store.opt_into_chaos_pool("chaos_ghost")
	var router = _make_router()
	assert_bool(router.can_merge("chaos_ghost", "normal_ghost", store)).is_false()
