## Tests for ChatSystem friend list operations.
extends GdUnitTestSuite

const ChatSystemScript := preload("res://autoloads/ChatSystem.gd")

var _chat: Node = null

func before_test() -> void:
	_chat = ChatSystemScript.new()
	add_child(_chat)

func after_test() -> void:
	if is_instance_valid(_chat):
		_chat.queue_free()
	_chat = null

# ---------------------------------------------------------------------------
# Add friend
# ---------------------------------------------------------------------------

func test_add_friend_appears_in_get_friends() -> void:
	_chat.add_friend("player_001", "Alice")
	var friends: Array = _chat.get_friends()
	var found := false
	for f: Dictionary in friends:
		if f["id"] == "player_001":
			found = true
	assert_bool(found).is_true()

# ---------------------------------------------------------------------------
# Remove friend
# ---------------------------------------------------------------------------

func test_remove_friend_excluded_from_get_friends() -> void:
	_chat.add_friend("player_002", "Bob")
	_chat.remove_friend("player_002")
	var friends: Array = _chat.get_friends()
	var found := false
	for f: Dictionary in friends:
		if f["id"] == "player_002":
			found = true
	assert_bool(found).is_false()

# ---------------------------------------------------------------------------
# Block does not affect friend list
# ---------------------------------------------------------------------------

func test_block_does_not_remove_from_friend_list() -> void:
	_chat.add_friend("player_003", "Carol")
	_chat.block("player_003")
	assert_bool(_chat.is_friend("player_003")).is_true()
	assert_bool(_chat.is_blocked("player_003")).is_true()

# ---------------------------------------------------------------------------
# is_friend false for unknown id
# ---------------------------------------------------------------------------

func test_is_friend_false_for_unknown_id() -> void:
	assert_bool(_chat.is_friend("nobody_known")).is_false()

# ---------------------------------------------------------------------------
# Duplicate add_friend is idempotent
# ---------------------------------------------------------------------------

func test_duplicate_add_friend_is_idempotent() -> void:
	_chat.add_friend("player_004", "Dave")
	_chat.add_friend("player_004", "Dave")
	var friends: Array = _chat.get_friends()
	var count := 0
	for f: Dictionary in friends:
		if f["id"] == "player_004":
			count += 1
	assert_int(count).is_equal(1)

# ---------------------------------------------------------------------------
# get_friends returns correct data
# ---------------------------------------------------------------------------

func test_get_friends_returns_name_and_id() -> void:
	_chat.add_friend("player_005", "Eve")
	var friends: Array = _chat.get_friends()
	var entry: Dictionary = {}
	for f: Dictionary in friends:
		if f["id"] == "player_005":
			entry = f
	assert_str(entry.get("name", "")).is_equal("Eve")
	assert_str(entry.get("pubkey", "")).is_equal("")  # empty until Phase C
