## Tests for MergeHandshake — propose/accept CRDT exchange to form a joint session.
##
## Rules:
##   - propose_merge() creates a proposal containing the local session_id and
##     a CRDT snapshot (plain Dictionary for testing).
##   - accept_merge() merges the proposal's CRDT data with local CRDT data
##     using LWW: the entry with the higher timestamp wins per key.
##   - get_combined_peers() returns the union of both peer lists (no duplicates).
##   - Merging is commutative: A.accept(B.proposal) == B.accept(A.proposal).
extends GdUnitTestSuite

const MergeHandshakeScript := preload("res://networking/MergeHandshake.gd")

func _make_handshake() -> Object:
	return MergeHandshakeScript.new()

# --- propose_merge ---

func test_proposal_contains_session_id() -> void:
	var hs = _make_handshake()
	var proposal: Dictionary = hs.propose_merge("session_A", {}, []) as Dictionary
	assert_that(proposal["session_id"]).is_equal("session_A")

func test_proposal_contains_crdt_snapshot() -> void:
	var hs = _make_handshake()
	var snapshot := {"tile_0_0": {"tile_id": "grass", "ts": 100}}
	var proposal: Dictionary = hs.propose_merge("session_A", snapshot, []) as Dictionary
	assert_that(proposal["crdt"]).is_equal(snapshot)

func test_proposal_contains_peer_list() -> void:
	var hs = _make_handshake()
	var proposal: Dictionary = hs.propose_merge("session_A", {}, ["peer_x", "peer_y"]) as Dictionary
	assert_bool((proposal["peers"] as Array).has("peer_x")).is_true()

# --- accept_merge: CRDT LWW ---

func test_accept_merge_includes_local_keys() -> void:
	var hs = _make_handshake()
	var local  := {"key_a": {"tile_id": "rock", "ts": 200}}
	var remote := {"key_b": {"tile_id": "sand", "ts": 100}}
	var proposal: Dictionary = hs.propose_merge("session_B", remote, []) as Dictionary
	var merged: Dictionary = hs.accept_merge(proposal, local) as Dictionary
	assert_bool(merged.has("key_a")).is_true()
	assert_bool(merged.has("key_b")).is_true()

func test_accept_merge_lww_remote_wins_higher_timestamp() -> void:
	var hs = _make_handshake()
	var local  := {"key_a": {"tile_id": "old",  "ts": 100}}
	var remote := {"key_a": {"tile_id": "new",  "ts": 200}}
	var proposal: Dictionary = hs.propose_merge("session_B", remote, []) as Dictionary
	var merged: Dictionary = hs.accept_merge(proposal, local) as Dictionary
	assert_that(merged["key_a"]["tile_id"]).is_equal("new")

func test_accept_merge_lww_local_wins_higher_timestamp() -> void:
	var hs = _make_handshake()
	var local  := {"key_a": {"tile_id": "newer", "ts": 300}}
	var remote := {"key_a": {"tile_id": "older", "ts": 150}}
	var proposal: Dictionary = hs.propose_merge("session_B", remote, []) as Dictionary
	var merged: Dictionary = hs.accept_merge(proposal, local) as Dictionary
	assert_that(merged["key_a"]["tile_id"]).is_equal("newer")

func test_accept_merge_commutative() -> void:
	var hs = _make_handshake()
	var crdt_a := {
		"key_a": {"tile_id": "fire", "ts": 100},
		"key_b": {"tile_id": "ice",  "ts": 50}
	}
	var crdt_b := {
		"key_a": {"tile_id": "water", "ts": 80},
		"key_b": {"tile_id": "ice",   "ts": 50}
	}
	var proposal_b: Dictionary = hs.propose_merge("session_B", crdt_b, []) as Dictionary
	var proposal_a: Dictionary = hs.propose_merge("session_A", crdt_a, []) as Dictionary
	var merged_ab: Dictionary = hs.accept_merge(proposal_b, crdt_a) as Dictionary
	var merged_ba: Dictionary = hs.accept_merge(proposal_a, crdt_b) as Dictionary
	assert_that(merged_ab["key_a"]["tile_id"]).is_equal(merged_ba["key_a"]["tile_id"])
	assert_that(merged_ab["key_b"]["tile_id"]).is_equal(merged_ba["key_b"]["tile_id"])

# --- get_combined_peers ---

func test_combined_peers_union() -> void:
	var hs = _make_handshake()
	var combined: Array = hs.get_combined_peers(["a", "b"], ["c", "d"]) as Array
	assert_that(combined.size()).is_equal(4)

func test_combined_peers_no_duplicates() -> void:
	var hs = _make_handshake()
	var combined: Array = hs.get_combined_peers(["a", "b"], ["b", "c"]) as Array
	assert_that(combined.size()).is_equal(3)

func test_combined_peers_empty_lists() -> void:
	var hs = _make_handshake()
	assert_that((hs.get_combined_peers([], []) as Array).size()).is_equal(0)
