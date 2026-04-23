## ConsentOverlay — shown on first non-headless launch to request telemetry consent.
extends Control

signal accepted
signal declined

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.78)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.offset_left = -210
	panel.offset_top  = -180
	add_child(panel)

	var title := Label.new()
	title.text = "Help improve Commons?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	panel.add_child(HSeparator.new())

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = (
		"If something crashes or fails to connect, we'd like to know.\n\n" +
		"What we collect:\n" +
		"  - Error type and location in code\n" +
		"  - Game version, platform, Godot version\n" +
		"  - Which phase failed (connecting, merging...)\n" +
		"  - A random ID reset every launch\n\n" +
		"What we never collect:\n" +
		"  - Your name or player ID\n" +
		"  - Your position or world data\n" +
		"  - Chat messages or server addresses\n\n" +
		"Reports are stored on the Freenet network (publicly readable).\n" +
		"Change this any time with /telemetry."
	)
	panel.add_child(body)

	panel.add_child(HSeparator.new())

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(btns)

	var yes_btn := Button.new()
	yes_btn.text = "Yes, share crash info"
	yes_btn.pressed.connect(_on_accepted)
	btns.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "No thanks"
	no_btn.pressed.connect(_on_declined)
	btns.add_child(no_btn)

func _on_accepted() -> void:
	accepted.emit()
	queue_free()

func _on_declined() -> void:
	declined.emit()
	queue_free()
