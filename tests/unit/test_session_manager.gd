## Tests for SessionManager — equal-peer P2P session state.
## Rules:
##   - start_session() initializes a clean session with no peers.
##   - add_peer() records the peer; peer_count increases.
##   - remove_peer() removes the peer; last peer standing keeps the session alive.
##   - is_active() is true after start_session() and stays true even with 0 connected peers.
##   - get_peers() returns the current connected peer list.
##   - Session ID is assigned on start_session() and stable until a new session starts.
extends GdUnitTestSuite

const SessionManagerScript := preload("res://networking/SessionManager.gd")

func _make_session() -> Object:
	var s = SessionManagerScript.new()
	s.start_session()
	return s

# --- Initialization ---

func test_session_not_active_before_start() -> void:
	var s = SessionManagerScript.new()
	assert_bool(s.is_active()).is_false()

func test_session_active_after_start() -> void:
	var s = _make_session()
	assert_bool(s.is_active()).is_true()

func test_session_id_assigned_on_start() -> void:
	var s = _make_session()
	assert_that(s.session_id).is_not_equal("")

func test_session_id_stable_across_calls() -> void:
	var s = _make_session()
	var id1: String = s.session_id
	var id2: String = s.session_id
	assert_that(id1).is_equal(id2)

func test_new_start_session_resets_state() -> void:
	var s = _make_session()
	s.add_peer("peer_1")
	var first_id: String = s.session_id
	s.start_session()
	assert_that(s.get_peers().size()).is_equal(0)
	assert_that(s.session_id).is_not_equal(first_id)

# --- Peer management ---

func test_no_peers_initially() -> void:
	var s = _make_session()
	assert_that(s.get_peers().size()).is_equal(0)

func test_add_peer_increases_count() -> void:
	var s = _make_session()
	s.add_peer("peer_1")
	assert_that(s.get_peers().size()).is_equal(1)

func test_add_multiple_peers() -> void:
	var s = _make_session()
	s.add_peer("peer_1")
	s.add_peer("peer_2")
	assert_that(s.get_peers().size()).is_equal(2)

func test_add_peer_stores_id() -> void:
	var s = _make_session()
	s.add_peer("peer_42")
	assert_bool(s.get_peers().has("peer_42")).is_true()

func test_remove_peer_decreases_count() -> void:
	var s = _make_session()
	s.add_peer("peer_1")
	s.remove_peer("peer_1")
	assert_that(s.get_peers().size()).is_equal(0)

func test_remove_nonexistent_peer_no_crash() -> void:
	var s = _make_session()
	s.remove_peer("ghost")  # should not crash
	assert_that(s.get_peers().size()).is_equal(0)

func test_last_peer_leaves_session_stays_active() -> void:
	var s = _make_session()
	s.add_peer("peer_1")
	s.remove_peer("peer_1")
	assert_bool(s.is_active()).is_true()

func test_duplicate_peer_add_idempotent() -> void:
	var s = _make_session()
	s.add_peer("peer_1")
	s.add_peer("peer_1")
	assert_that(s.get_peers().size()).is_equal(1)

# --- peer_count convenience ---

func test_peer_count_zero_initially() -> void:
	var s = _make_session()
	assert_that(s.peer_count()).is_equal(0)

func test_peer_count_reflects_adds() -> void:
	var s = _make_session()
	s.add_peer("a")
	s.add_peer("b")
	assert_that(s.peer_count()).is_equal(2)
