## Tests for NetworkManager — WebRTC peer state machine.
## Only the pure state machine is tested here — actual WebRTC connections
## are verified by the WebRTC loopback integration test.
extends GdUnitTestSuite

const NetworkManagerScript := preload("res://autoloads/NetworkManager.gd")

var _to_free: Array = []

func after_test() -> void:
	for n in _to_free:
		if is_instance_valid(n):
			n.free()
	_to_free.clear()

func _make_manager() -> Object:
	var n = NetworkManagerScript.new()
	_to_free.append(n)
	return n

# --- Initial state ---

func test_initial_state_is_idle() -> void:
	var n = _make_manager()
	assert_that(n.get_state()).is_equal(n.STATE_IDLE)

func test_not_connected_initially() -> void:
	var n = _make_manager()
	assert_bool(n.is_connected_to_session()).is_false()

func test_not_hosting_initially() -> void:
	var n = _make_manager()
	assert_bool(n.is_hosting()).is_false()

# --- Constants ---

func test_default_port_is_sensible() -> void:
	var n = _make_manager()
	assert_that(n.DEFAULT_PORT).is_greater(1024)
	assert_that(n.DEFAULT_PORT).is_less(65535)

func test_state_constants_are_distinct() -> void:
	var n = _make_manager()
	assert_that(n.STATE_IDLE).is_not_equal(n.STATE_ACTIVE)
