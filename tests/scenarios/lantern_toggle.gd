## Scenario: lantern right-click toggles its light; removing the lantern from
## the tool slots auto-disables it.
##
## Run:
##   godot4 --path . -- --puppet-scenario=res://tests/scenarios/lantern_toggle.gd
##
## Puppet quits 0 on pass, 1 on fail.
extends Node

func _run(p: Node) -> void:
	await p.wait_ready()
	await p.wait_frames(5)

	p.select_tool(0)
	p.check(p.active_tool_id() == "lantern",
		"expected active tool to be lantern, got: " + p.active_tool_id())

	var lantern: Node = p.player().get_node_or_null("Lantern")
	p.check(lantern != null, "Player has no Lantern child")
	p.check(not bool(lantern.is_on), "lantern should start off")

	# Right-click any tile with lantern active → toggle on.
	var player_pos: Vector2 = p.player().position
	var some_tile := Vector2i(
		int(floor(player_pos.x / Constants.TILE_SIZE)),
		int(floor(player_pos.y / Constants.TILE_SIZE)))

	p.click_tile(some_tile, MOUSE_BUTTON_RIGHT)
	await p.wait_frames(2)
	p.check(bool(lantern.is_on), "expected lantern on after first right-click")

	# Right-click again → toggle off.
	p.click_tile(some_tile, MOUSE_BUTTON_RIGHT)
	await p.wait_frames(2)
	p.check(not bool(lantern.is_on), "expected lantern off after second right-click")

	# Toggle on again, then remove the lantern from the tool slot. One frame later
	# Player._auto_off_lantern_if_dropped should have forced it off.
	p.click_tile(some_tile, MOUSE_BUTTON_RIGHT)
	await p.wait_frames(2)
	p.check(bool(lantern.is_on), "expected lantern on before auto-off test")

	p.player().inventory.clear_tool_slot(0)
	await p.wait_frames(3)
	p.check(not bool(lantern.is_on),
		"expected auto-off after clearing lantern tool slot, is_on=" + str(lantern.is_on))

	# Verify the log captured the three toggle events.
	var toggles: Array = EventLog.events_of("lantern_toggle")
	p.check(toggles.size() == 3,
		"expected 3 lantern_toggle events, got " + str(toggles.size()))

	p.pass_scenario("lantern right-click toggles + auto-off on drop")
