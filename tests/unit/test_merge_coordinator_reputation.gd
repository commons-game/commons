## Tests for MergeCoordinator × reputation routing.
## Verifies that _on_peer_discovered respects MergeRouter.can_merge()
## before emitting connection_needed.
extends GdUnitTestSuite

const MergeCoordinatorScript := preload("res://networking/MergeCoordinator.gd")
const ReputationStoreScript  := preload("res://reputation/ReputationStore.gd")
const MergeRouterScript      := preload("res://reputation/MergeRouter.gd")

var _coord: Object
var _store: Object
var _router: Object
var _to_free: Array = []

func before_test() -> void:
	_coord = MergeCoordinatorScript.new()
	_coord.session_id = "aaa_local"
	_coord.dev_instant_merge = true
	_store = ReputationStoreScript.new()
	_router = MergeRouterScript.new()
	_coord.reputation_store = _store
	_coord.merge_router     = _router
	_to_free.append(_coord)

func after_test() -> void:
	for n in _to_free:
		if is_instance_valid(n):
			n.free()
	_to_free.clear()

# --- Normal merge (both clean) ---

func test_two_normal_players_can_merge() -> void:
	var emitted: Array = [false]
	_coord.connection_needed.connect(func(_i, _p, _h): emitted[0] = true)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 7777)
	assert_bool(emitted[0]).is_true()

# --- Reputation blocking ---

func test_blocked_when_remote_is_in_chaos_pool() -> void:
	_store.opt_into_chaos_pool("bbb_remote")
	var emitted: Array = [false]
	_coord.connection_needed.connect(func(_i, _p, _h): emitted[0] = true)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 7777)
	assert_bool(emitted[0]).is_false()

func test_blocked_when_local_is_chaos_and_remote_is_normal() -> void:
	_store.opt_into_chaos_pool("aaa_local")
	var emitted: Array = [false]
	_coord.connection_needed.connect(func(_i, _p, _h): emitted[0] = true)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 7777)
	assert_bool(emitted[0]).is_false()

func test_blocked_when_remote_has_enough_reports() -> void:
	for i in range(_store.REPORT_THRESHOLD):
		_store.submit_report("witness_%d" % i, "bbb_remote", "griefed my shrine")
	var emitted: Array = [false]
	_coord.connection_needed.connect(func(_i, _p, _h): emitted[0] = true)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 7777)
	assert_bool(emitted[0]).is_false()

# --- Chaos × chaos allowed ---

func test_both_chaos_can_merge() -> void:
	_store.opt_into_chaos_pool("aaa_local")
	_store.opt_into_chaos_pool("bbb_remote")
	var emitted: Array = [false]
	_coord.connection_needed.connect(func(_i, _p, _h): emitted[0] = true)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 7777)
	assert_bool(emitted[0]).is_true()

# --- No store set → backward-compat passthrough ---

func test_nil_store_allows_merge() -> void:
	_coord.reputation_store = null
	_coord.merge_router     = null
	var emitted: Array = [false]
	_coord.connection_needed.connect(func(_i, _p, _h): emitted[0] = true)
	_coord._on_peer_discovered("bbb_remote", Vector2i(1, 0), "192.168.1.5", 7777)
	assert_bool(emitted[0]).is_true()
