## Tests for Hotbar Control mouse_filter settings.
##
## Catches the regression where slot panels and their ColorRect children had
## mouse_filter=STOP (Godot default), causing the GUI system to consume all
## left-click events before _unhandled_input fired. Drag-and-drop was silently
## broken from day one — scroll wheel and keys worked because they bypass the
## GUI mouse filter.
##
## Rule: every Control inside the Hotbar CanvasLayer must use MOUSE_FILTER_IGNORE
## so _unhandled_input handles all slot interaction. Only exception: the drag
## cursor, which uses MOUSE_FILTER_IGNORE explicitly for the same reason.
extends GdUnitTestSuite

const HotbarScript    := preload("res://ui/Hotbar.gd")
const InventoryScript := preload("res://items/Inventory.gd")

var _hotbar: CanvasLayer = null

func before_test() -> void:
	_hotbar = HotbarScript.new()
	_hotbar.inventory = InventoryScript.new()
	add_child(_hotbar)
	await get_tree().process_frame

func after_test() -> void:
	if is_instance_valid(_hotbar): _hotbar.queue_free()
	_hotbar = null

# ---------------------------------------------------------------------------
# Slot panels
# ---------------------------------------------------------------------------

func test_all_slot_panels_have_mouse_filter_ignore() -> void:
	for i in range(_hotbar._panels.size()):
		var p := _hotbar._panels[i] as ColorRect
		assert_int(p.mouse_filter).override_failure_message(
			"Slot panel[%d] has MOUSE_FILTER_STOP — blocks left-click drag events" % i
		).is_equal(Control.MOUSE_FILTER_IGNORE)

func test_no_slot_panel_child_has_mouse_filter_stop() -> void:
	for i in range(_hotbar._panels.size()):
		var p := _hotbar._panels[i] as ColorRect
		for child in p.get_children():
			if child is Control:
				var c := child as Control
				assert_int(c.mouse_filter).override_failure_message(
					"Slot panel[%d] child '%s' has MOUSE_FILTER_STOP — blocks drag clicks" % [i, c.name]
				).is_not_equal(Control.MOUSE_FILTER_STOP)

# ---------------------------------------------------------------------------
# Expanded panel background
# ---------------------------------------------------------------------------

func test_expanded_bg_does_not_block_mouse() -> void:
	assert_int(_hotbar._expanded_bg.mouse_filter).override_failure_message(
		"_expanded_bg has MOUSE_FILTER_STOP — blocks clicks on expanded slot panels"
	).is_equal(Control.MOUSE_FILTER_IGNORE)

# ---------------------------------------------------------------------------
# Correct slot count
# ---------------------------------------------------------------------------

func test_hotbar_has_correct_number_of_slots() -> void:
	# 8 hotbar + 4 extra_bag + 2 tool + 1 weapon + 1 talisman = 16 total
	assert_int(_hotbar._panels.size()).is_equal(16)

func test_panels_and_slots_arrays_are_same_length() -> void:
	assert_int(_hotbar._panels.size()).is_equal(_hotbar._slots.size())
	assert_int(_hotbar._panels.size()).is_equal(_hotbar._icon_bgs.size())
	assert_int(_hotbar._panels.size()).is_equal(_hotbar._icon_textures.size())
	assert_int(_hotbar._panels.size()).is_equal(_hotbar._name_labels.size())
	assert_int(_hotbar._panels.size()).is_equal(_hotbar._count_labels.size())
	assert_int(_hotbar._panels.size()).is_equal(_hotbar._borders.size())
