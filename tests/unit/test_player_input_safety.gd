## Tests for Player input handler safety.
##
## Catches two regressions:
##   1. _do_attack looped over parent children looking for Tether nodes, matched
##      the Player itself (has take_damage, is Node2D), and called take_damage
##      with 2 args (damage + tool_id) — but Player.take_damage expects 1 arg.
##      Player was silently hurting itself every swing.
##   2. _unhandled_input accessed event.echo on InputEventMouseButton — that
##      property only exists on InputEventKey. Crash every mouse button press.
extends GdUnitTestSuite

const PlayerScript    := preload("res://player/Player.gd")
const InventoryScript := preload("res://items/Inventory.gd")

var _parent: Node    = null
var _player: Node    = null

func before_test() -> void:
	# Player reads get_parent().get_children() in _do_attack.
	# Give it a real parent so the loop runs.
	_parent = Node.new()
	add_child(_parent)
	_player = PlayerScript.new()
	_player.inventory = InventoryScript.new()
	_parent.add_child(_player)
	await get_tree().process_frame

func after_test() -> void:
	if is_instance_valid(_parent): _parent.queue_free()
	_parent = null
	_player = null

# ---------------------------------------------------------------------------
# Player does not attack itself
# ---------------------------------------------------------------------------

func test_player_hp_unchanged_after_attack_swing() -> void:
	# With only the Player in the parent tree and no mobs or Tethers,
	# _do_attack should find nothing to hit. HP must be unchanged.
	var hp_before: int = _player.hp
	_player._attack_cooldown = 0.0  # reset cooldown so swing is allowed
	_player._do_attack()
	assert_int(_player.hp).override_failure_message(
		"Player damaged itself during attack — self-skip in Tether loop missing"
	).is_equal(hp_before)

func test_player_attack_does_not_crash_with_self_in_parent() -> void:
	# The regression: Player.take_damage was called with 2 args. Verify no crash.
	_player._attack_cooldown = 0.0
	_player._do_attack()
	assert_bool(is_instance_valid(_player)).is_true()

# ---------------------------------------------------------------------------
# Mouse button events do not access .echo
# ---------------------------------------------------------------------------

func test_right_click_unhandled_input_does_not_crash() -> void:
	# The regression: event.echo was accessed on InputEventMouseButton, which
	# doesn't have that property. Verify the handler runs without crashing.
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	_player._unhandled_input(event)
	assert_bool(is_instance_valid(_player)).is_true()

func test_left_click_unhandled_input_does_not_crash() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	_player._unhandled_input(event)
	assert_bool(is_instance_valid(_player)).is_true()

func test_mouse_button_event_has_no_echo_property() -> void:
	# Document that InputEventMouseButton lacks .echo — it only exists on key events.
	var mouse_event := InputEventMouseButton.new()
	var key_event   := InputEventKey.new()
	var mouse_props: Array = mouse_event.get_property_list().map(func(p): return p["name"])
	var key_props:   Array = key_event.get_property_list().map(func(p): return p["name"])
	assert_bool(key_props.has("echo")).is_true()    # key events have .echo
	assert_bool(mouse_props.has("echo")).is_false()  # mouse events do not
