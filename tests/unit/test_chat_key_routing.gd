## Tests that Player._unhandled_input routes KEY_T to ChatInput.activate()
## and that ChatInput is reachable via the expected node path.
##
## Player._ready() references @onready siblings (ChunkManager, ShrineManager, Camera2D)
## which won't exist in test setup — those errors are harmless and expected.
## We bypass _ready() side-effects by calling _unhandled_input directly via Callable.
extends GdUnitTestSuite

const PlayerScript    := preload("res://player/Player.gd")
const ChatInputScript := preload("res://ui/ChatInput.gd")

var _parent: Node     = null
var _player: Node     = null
var _chat:   Node     = null

func before_test() -> void:
	# Recreate the World/Player/ChatInput sibling structure.
	_parent = Node2D.new()
	_parent.name = "World"
	add_child(_parent)

	# Add ChatInput first so Player._ready() could theoretically find it
	# (though @onready resolution happens before our add_child below).
	_chat = ChatInputScript.new()
	_chat.name = "ChatInput"
	_parent.add_child(_chat)

	# Player needs a Camera2D child for @onready $Camera2D.
	# Add a dummy Camera2D to prevent a hard crash in _ready().
	var cam := Camera2D.new()
	cam.name = "Camera2D"

	_player = PlayerScript.new()
	_player.name = "Player"
	_player.add_child(cam)      # attach before entering tree
	_parent.add_child(_player)

	await get_tree().process_frame

func after_test() -> void:
	if is_instance_valid(_parent): _parent.queue_free()
	_parent = null
	_player = null
	_chat   = null

func _make_key_event(keycode: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	ev.echo    = false
	return ev

# ---------------------------------------------------------------------------
# Node topology
# ---------------------------------------------------------------------------

func test_chat_input_reachable_from_player() -> void:
	var found := _player.get_node_or_null("../ChatInput")
	assert_object(found).is_not_null()

func test_chat_input_is_hidden_by_default() -> void:
	assert_bool(_chat.visible).is_false()

# ---------------------------------------------------------------------------
# T key → activate
# ---------------------------------------------------------------------------

func test_t_key_activates_chat() -> void:
	assert_bool(_chat.visible).is_false()
	_player._unhandled_input(_make_key_event(KEY_T))
	assert_bool(_chat.visible).is_true()

func test_t_key_does_not_crash_if_already_open() -> void:
	_chat.activate()
	# Guard: when visible=true the handler skips activate — must not crash.
	_player._unhandled_input(_make_key_event(KEY_T))
	assert_bool(_chat.visible).is_true()

# ---------------------------------------------------------------------------
# Esc dismisses chat
# ---------------------------------------------------------------------------

func test_esc_hides_chat() -> void:
	_chat.activate()
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	_chat._on_line_edit_input(ev)
	assert_bool(_chat.visible).is_false()

# ---------------------------------------------------------------------------
# T key guard: dead player does not open chat
# ---------------------------------------------------------------------------

func test_t_key_ignored_when_player_dead() -> void:
	_player.set("_dead", true)
	_player._unhandled_input(_make_key_event(KEY_T))
	assert_bool(_chat.visible).is_false()
	_player.set("_dead", false)
