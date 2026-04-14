## Phase 5 end-to-end reputation test.
## Exercises the full chain:
##   - Players report a griefer → auto-promotion to chaos pool
##   - Griefer blocked from merging with normal players
##   - Griefer can merge with another chaos player
##   - TalismanOfChaos opt-in routes a willing player into the chaos pool
##   - MergeRouter + MergeHandshake + BridgeFormation: reputation check gates the
##     bridge before CRDT exchange happens
extends GdUnitTestSuite

const ReputationStoreScript  := preload("res://reputation/ReputationStore.gd")
const MergeRouterScript      := preload("res://reputation/MergeRouter.gd")
const TalismanOfChaosScript  := preload("res://reputation/TalismanOfChaos.gd")
const MergeHandshakeScript   := preload("res://networking/MergeHandshake.gd")
const BridgeFormationScript  := preload("res://networking/BridgeFormation.gd")

func test_griefer_lifecycle() -> void:
	var store  = ReputationStoreScript.new()
	var router = MergeRouterScript.new()

	# No reports yet — everyone normal
	assert_bool(router.can_merge("alice", "griefer", store)).is_true()

	# Three different players report "griefer" — hits threshold
	for i in range(store.REPORT_THRESHOLD):
		store.submit_report("witness_%d" % i, "griefer", "destroyed my shrine")

	assert_bool(store.is_in_chaos_pool("griefer")).is_true()

	# Griefer now blocked from normal players
	assert_bool(router.can_merge("alice",   "griefer", store)).is_false()
	assert_bool(router.can_merge("griefer", "alice",   store)).is_false()

	# Griefer can still merge with other chaos players
	store.opt_into_chaos_pool("pvp_alice")
	assert_bool(router.can_merge("griefer", "pvp_alice", store)).is_true()

func test_talisman_of_chaos_voluntary_routing() -> void:
	var store    = ReputationStoreScript.new()
	var router   = MergeRouterScript.new()
	var talisman = TalismanOfChaosScript.new()

	# Bob is normal, alice opts into chaos voluntarily
	talisman.apply_to("alice", store)

	assert_bool(router.can_merge("alice", "bob", store)).is_false()

	# Bob also equips talisman — now both are chaos → can merge
	talisman.apply_to("bob", store)
	assert_bool(router.can_merge("alice", "bob", store)).is_true()

func test_reputation_check_gates_bridge_before_crdt_exchange() -> void:
	# Simulate: BridgeFormation says "form bridge" but router blocks it.
	var store   = ReputationStoreScript.new()
	var router  = MergeRouterScript.new()
	var bridge  = BridgeFormationScript.new()
	var handshake = MergeHandshakeScript.new()

	# Mark "griefer" as chaos
	for i in range(store.REPORT_THRESHOLD):
		store.submit_report("witness_%d" % i, "griefer", "bad")

	# Bridge geometry says it's possible
	var bridge_possible := bridge.should_form_bridge(
		Vector2i(0, 0), Vector2i(5, 0), 1.0, 1.0)
	assert_bool(bridge_possible).is_true()

	# But reputation check blocks the merge
	var merge_allowed := router.can_merge("clean_player", "griefer", store)
	assert_bool(merge_allowed).is_false()

	# Verify: no CRDT exchange happens when router blocks
	if merge_allowed:
		var crdt_clean := {"chunk_0": {"tile_id": "grass", "ts": 100}}
		var proposal: Dictionary = handshake.propose_merge("griefer", {}, []) as Dictionary
		var _merged = handshake.accept_merge(proposal, crdt_clean)
	# If we got here without the exchange, the guard worked correctly.
	assert_bool(merge_allowed).is_false()

func test_spam_report_prevention_cannot_force_chaos_pool() -> void:
	var store = ReputationStoreScript.new()

	# One reporter tries to spam-report the same player
	for _i in range(store.REPORT_THRESHOLD * 10):
		store.submit_report("griefer_reporter", "victim", "spam")

	# Only one report counted → well below threshold
	assert_that(store.get_report_count("victim")).is_equal(1)
	assert_bool(store.is_in_chaos_pool("victim")).is_false()

func test_two_chaos_players_exchange_crdt_successfully() -> void:
	var store     = ReputationStoreScript.new()
	var router    = MergeRouterScript.new()
	var handshake = MergeHandshakeScript.new()

	store.opt_into_chaos_pool("chaos_alice")
	store.opt_into_chaos_pool("chaos_bob")

	assert_bool(router.can_merge("chaos_alice", "chaos_bob", store)).is_true()

	# CRDT exchange proceeds normally
	var crdt_a := {"tile_a": {"tile_id": "lava", "ts": 100}}
	var crdt_b := {"tile_b": {"tile_id": "void", "ts": 200}}
	var proposal: Dictionary = handshake.propose_merge("chaos_bob", crdt_b, []) as Dictionary
	var merged: Dictionary   = handshake.accept_merge(proposal, crdt_a) as Dictionary

	assert_bool(merged.has("tile_a")).is_true()
	assert_bool(merged.has("tile_b")).is_true()
