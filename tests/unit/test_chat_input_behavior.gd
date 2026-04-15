## Tests for ChatInput activation, deactivation, and text submission.
extends GdUnitTestSuite

const ChatInputScript  := preload("res://ui/ChatInput.gd")
const ChatSystemScript := preload("res://autoloads/ChatSystem.gd")

var _input: Node = null
var _sys:   Node = null

func before_test() -> void:
	_sys = ChatSystemScript.new()
	add_child(_sys)
	_input = ChatInputScript.new()
	add_child(_input)
	await get_tree().process_frame

func after_test() -> void:
	if is_instance_valid(_input): _input.queue_free()
	if is_instance_valid(_sys):   _sys.queue_free()
	_input = null
	_sys   = null

# ---------------------------------------------------------------------------
# Visibility / activation
# ---------------------------------------------------------------------------

func test_chat_input_hidden_by_default() -> void:
	assert_bool(_input.visible).is_false()

func test_activate_makes_visible() -> void:
	_input.activate()
	assert_bool(_input.visible).is_true()

func test_deactivate_hides() -> void:
	_input.activate()
	_input.deactivate()
	assert_bool(_input.visible).is_false()

func test_activate_twice_stays_visible() -> void:
	_input.activate()
	_input.activate()
	assert_bool(_input.visible).is_true()

func test_deactivate_when_already_hidden_is_safe() -> void:
	# already hidden — must not crash
	_input.deactivate()
	assert_bool(_input.visible).is_false()

# ---------------------------------------------------------------------------
# Text submission
# ---------------------------------------------------------------------------

func test_empty_submit_does_not_stay_visible() -> void:
	# submitting empty/whitespace should just deactivate, not remain open
	_input.activate()
	_input._on_text_submitted("")
	assert_bool(_input.visible).is_false()

func test_submit_deactivates_input() -> void:
	_input.activate()
	_input._on_text_submitted("hello world")
	assert_bool(_input.visible).is_false()

func test_whitespace_submit_deactivates() -> void:
	_input.activate()
	_input._on_text_submitted("   ")
	assert_bool(_input.visible).is_false()
