## Tests for RegionAuthority — chunk-to-peer authority mapping.
## Rules:
##   - Authority for a chunk is the peer whose current chunk is closest
##     (Chebyshev distance) to the target chunk.
##   - If no peers are registered, authority is LOCAL_PEER_ID (self).
##   - on_peer_moved() updates the peer's position; may change which peer
##     holds authority for affected chunks.
##   - on_peer_left() removes the peer; authority redistributes to remaining peers.
##   - get_authority_for_chunk() is deterministic for the same peer set.
extends GdUnitTestSuite

const RegionAuthorityScript := preload("res://networking/RegionAuthority.gd")

const LOCAL_ID := 1   # conventional local peer id in Godot multiplayer

func _make_authority() -> Object:
	var r = RegionAuthorityScript.new()
	return r

# --- No peers — local authority ---

func test_no_peers_authority_is_local() -> void:
	var r = _make_authority()
	assert_that(r.get_authority_for_chunk(Vector2i(0, 0))).is_equal(LOCAL_ID)

# --- Single remote peer ---

func test_single_peer_owns_nearby_chunk() -> void:
	var r = _make_authority()
	r.on_peer_moved(2, Vector2i(0, 0))
	# peer 2 is at (0,0), local (1) has no registered position — peer 2 wins
	assert_that(r.get_authority_for_chunk(Vector2i(0, 0))).is_equal(2)

func test_local_peer_position_registered() -> void:
	var r = _make_authority()
	r.on_peer_moved(LOCAL_ID, Vector2i(0, 0))
	r.on_peer_moved(2, Vector2i(10, 10))
	# local peer is at (0,0), remote at (10,10) — local closer to (0,0)
	assert_that(r.get_authority_for_chunk(Vector2i(0, 0))).is_equal(LOCAL_ID)

# --- Closest peer wins ---

func test_closest_peer_wins() -> void:
	var r = _make_authority()
	r.on_peer_moved(LOCAL_ID, Vector2i(0, 0))
	r.on_peer_moved(2, Vector2i(5, 0))
	r.on_peer_moved(3, Vector2i(2, 0))
	# chunk (3,0): distance to LOCAL(0,0)=3, peer2(5,0)=2, peer3(2,0)=1 → peer3
	assert_that(r.get_authority_for_chunk(Vector2i(3, 0))).is_equal(3)

# --- Tie-breaking is consistent ---

func test_tie_broken_consistently() -> void:
	var r = _make_authority()
	r.on_peer_moved(2, Vector2i(0, 0))
	r.on_peer_moved(3, Vector2i(0, 0))  # exact same position
	# Doesn't matter who wins — just verify it's deterministic
	var first: int = r.get_authority_for_chunk(Vector2i(5, 5))
	var second: int = r.get_authority_for_chunk(Vector2i(5, 5))
	assert_that(first).is_equal(second)

# --- on_peer_moved updates position ---

func test_peer_move_updates_authority() -> void:
	var r = _make_authority()
	r.on_peer_moved(LOCAL_ID, Vector2i(0, 0))
	r.on_peer_moved(2, Vector2i(10, 0))
	# Chunk (8,0): local distance=8, peer2 distance=2 → peer2 owns it
	assert_that(r.get_authority_for_chunk(Vector2i(8, 0))).is_equal(2)
	# peer 2 moves far away
	r.on_peer_moved(2, Vector2i(100, 0))
	# Now local is closer to (8,0)
	assert_that(r.get_authority_for_chunk(Vector2i(8, 0))).is_equal(LOCAL_ID)

# --- on_peer_left redistributes ---

func test_peer_left_redistributes_authority() -> void:
	var r = _make_authority()
	r.on_peer_moved(LOCAL_ID, Vector2i(0, 0))
	r.on_peer_moved(2, Vector2i(1, 0))
	# peer 2 is closer to (1,0)
	assert_that(r.get_authority_for_chunk(Vector2i(1, 0))).is_equal(2)
	r.on_peer_left(2)
	# only local remains
	assert_that(r.get_authority_for_chunk(Vector2i(1, 0))).is_equal(LOCAL_ID)

func test_peer_left_unknown_peer_no_crash() -> void:
	var r = _make_authority()
	r.on_peer_left(999)  # should not crash
	assert_that(r.get_authority_for_chunk(Vector2i(0, 0))).is_equal(LOCAL_ID)
