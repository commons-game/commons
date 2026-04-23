## Regression: right-clicking with the lantern in a bag hotbar slot must
## toggle the light. Previously inventory.get_active_tool() only read
## tool_slots, so dragging the lantern into a bag slot silently made every
## click emit tool_id="" and the toggle branch never fired.
##
## Run:
##   godot4 --headless --path . -- --puppet-scenario=res://tests/scenarios/lantern_in_bag_toggle.gd
extends Node

func _run(p: Node) -> void:
	await p.wait_ready()
	await p.wait_frames(5)

	# Move the lantern out of its starter tool_slot and into bag slot 0,
	# then make bag slot 0 the active hotbar selection — mirroring what
	# the user did when they saw the bug.
	var inv: Object = p.player().inventory
	inv.set_tool_slot(0, {})
	inv.bag[0] = {"id": "lantern", "category": "tool", "count": 1}

	var hotbar: Node = p.player().get_parent().get_node_or_null("Hotbar")
	p.check(hotbar != null, "World has no Hotbar node — scenario can't simulate the bug")
	hotbar.call("_set_active", 0)
	await p.wait_frames(2)

	p.check(str(p.player().call("wielded_item_id")) == "lantern",
		"expected wielded item = lantern after moving to bag[0], got '%s'" % \
			str(p.player().call("wielded_item_id")))

	var lantern: Node = p.player().get_node_or_null("Lantern")
	p.check(lantern != null, "player has no Lantern child")
	p.check(not bool(lantern.is_on), "lantern should start off")

	# Right-click any tile. TileInteraction should see tool_id="lantern" and
	# toggle the light on.
	var player_pos: Vector2 = p.player().position
	var near_tile := Vector2i(
		int(floor(player_pos.x / Constants.TILE_SIZE)),
		int(floor(player_pos.y / Constants.TILE_SIZE)))
	p.click_tile(near_tile, MOUSE_BUTTON_RIGHT)
	await p.wait_frames(2)

	# Verify the EventLog recorded the correct tool_id for the click.
	# EventLog entries are {type, data, frame} — tool_id lives in data.
	var clicks: Array = EventLog.events_of("click")
	p.check(clicks.size() >= 1, "no click events recorded")
	var click_data: Dictionary = (clicks[-1] as Dictionary).get("data", {}) as Dictionary
	p.check(str(click_data.get("tool_id", "")) == "lantern",
		"click should dispatch with tool_id='lantern', got '%s'" % \
			str(click_data.get("tool_id", "")))

	p.check(bool(lantern.is_on),
		"expected lantern on after right-click while held in bag[0]")

	# Second right-click should toggle off.
	p.click_tile(near_tile, MOUSE_BUTTON_RIGHT)
	await p.wait_frames(2)
	p.check(not bool(lantern.is_on), "expected lantern off after second right-click")

	p.pass_scenario("lantern in hotbar bag slot toggles on right-click")
