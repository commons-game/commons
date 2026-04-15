## Tests for ChatSystem command parsing and routing.
extends GdUnitTestSuite

const ChatSystemScript := preload("res://autoloads/ChatSystem.gd")

var _chat: Node = null
var _last_send_proximity_args: Array = []
var _last_send_dm_args: Array = []
var _system_messages: Array = []
var _received_signals: Array = []

func before_test() -> void:
	_chat = ChatSystemScript.new()
	add_child(_chat)
	_last_send_proximity_args = []
	_last_send_dm_args = []
	_system_messages = []
	_received_signals = []
	_chat.message_received.connect(_on_message_received)

func after_test() -> void:
	if is_instance_valid(_chat):
		_chat.queue_free()
	_chat = null

func _on_message_received(sender_name: String, text: String, is_dm: bool, sender_id: String) -> void:
	_received_signals.append({
		"sender_name": sender_name,
		"text": text,
		"is_dm": is_dm,
		"sender_id": sender_id,
	})

# ---------------------------------------------------------------------------
# /addfriend
# ---------------------------------------------------------------------------

func test_addfriend_adds_to_friend_list() -> void:
	_chat.handle_input("/addfriend alice", "local_id", "LocalPlayer")
	assert_bool(_chat.is_friend("alice")).is_true()

# ---------------------------------------------------------------------------
# /removefriend
# ---------------------------------------------------------------------------

func test_removefriend_removes_from_friend_list() -> void:
	_chat.add_friend("alice", "alice")
	_chat.handle_input("/removefriend alice", "local_id", "LocalPlayer")
	assert_bool(_chat.is_friend("alice")).is_false()

# ---------------------------------------------------------------------------
# /block
# ---------------------------------------------------------------------------

func test_block_adds_to_block_list() -> void:
	_chat.handle_input("/block alice", "local_id", "LocalPlayer")
	assert_bool(_chat.is_blocked("alice")).is_true()

# ---------------------------------------------------------------------------
# /unblock
# ---------------------------------------------------------------------------

func test_unblock_removes_from_block_list() -> void:
	_chat.block("alice")
	_chat.handle_input("/unblock alice", "local_id", "LocalPlayer")
	assert_bool(_chat.is_blocked("alice")).is_false()

# ---------------------------------------------------------------------------
# /dm
# ---------------------------------------------------------------------------

func test_dm_command_triggers_send_dm() -> void:
	# /dm routes to FreenetDMQueue when target is offline (no ChatRPC in test scene).
	# FreenetDMQueue is an autoload — verify it received the queued DM.
	_chat.handle_input("/dm alice hello world", "local_id", "LocalPlayer")
	var queue: Array = FreenetDMQueue.get_queue()
	var found := false
	for entry: Dictionary in queue:
		if str(entry["target_name"]) == "alice":
			found = true
	assert_bool(found).is_true()

func test_dm_command_multi_word_message() -> void:
	# Verify the command parser correctly joins multi-word message parts.
	# The full text after the target name should be the DM message.
	FreenetDMQueue.clear_queue()
	_chat.handle_input("/dm bob this is a long message", "local_id", "LocalPlayer")
	var queue: Array = FreenetDMQueue.get_queue()
	assert_int(queue.size()).is_greater(0)
	var entry: Dictionary = queue[0]
	assert_str(str(entry["text"])).is_equal("this is a long message")

# ---------------------------------------------------------------------------
# Unknown command
# ---------------------------------------------------------------------------

func test_unknown_command_pushes_system_message() -> void:
	_chat.handle_input("/foo", "local_id", "LocalPlayer")
	var any_unknown := false
	for entry: Dictionary in _received_signals:
		if str(entry["text"]).contains("Unknown") or str(entry["text"]).contains("unknown"):
			any_unknown = true
	assert_bool(any_unknown).is_true()

# ---------------------------------------------------------------------------
# Plain text → proximity
# ---------------------------------------------------------------------------

func test_plain_text_sends_proximity_not_command() -> void:
	_received_signals.clear()
	_chat.handle_input("hello world", "local_id", "LocalPlayer")
	# message_received should be emitted with is_dm=false
	assert_int(_received_signals.size()).is_greater(0)
	var sig: Dictionary = _received_signals[0]
	assert_bool(bool(sig["is_dm"])).is_false()

# ---------------------------------------------------------------------------
# Blocked sender — receive_proximity should not emit message_received
# ---------------------------------------------------------------------------

func test_blocked_sender_receive_proximity_does_not_emit() -> void:
	_chat.block("bad_guy_id")
	_received_signals.clear()
	_chat.receive_proximity("bad_guy_id", "BadGuy", "spam message")
	assert_int(_received_signals.size()).is_equal(0)

func test_non_blocked_sender_receive_proximity_emits() -> void:
	_received_signals.clear()
	_chat.receive_proximity("good_guy_id", "GoodGuy", "hello there")
	assert_int(_received_signals.size()).is_equal(1)
