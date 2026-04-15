## EquipmentUI — press I to toggle equipment and bag panel.
##
## Left panel: "EQUIPPED" header + 5 labeled buttons (Body/Armor/Head/Feet/Held)
##   showing the current item_id or "—".
## Right panel: "BAG" header + 4×3 grid of 12 item buttons.
##
## Clicking an equipped slot button calls player.equipment.unequip(slot), refreshes.
## Clicking a bag slot button calls player.equipment.equip(item_id), refreshes.
##
## Wire up via init(player_node) called by World._ready().
## Toggle visibility by pressing I (handled in Player._unhandled_input).
extends CanvasLayer

const EQUIPPED_SLOTS := ["armor", "head", "feet", "held_item"]
const SLOT_LABELS := {"armor": "Armor", "head": "Head", "feet": "Feet", "held_item": "Held"}

var _player: Node = null
var _panel: Panel = null
var _equipped_buttons: Dictionary = {}  # slot -> Button
var _bag_buttons: Array = []            # Array of Button (12)

func _init() -> void:
	layer = 10

func init(player_node: Node) -> void:
	_player = player_node
	_build_ui()
	hide()

## Toggle panel visibility.
func toggle() -> void:
	if visible:
		hide()
	else:
		_refresh()
		show()

func _build_ui() -> void:
	_panel = Panel.new()
	_panel.name = "EquipmentPanel"
	# Position in upper-left area; size to hold both columns.
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(4, 100)
	_panel.custom_minimum_size = Vector2(320, 220)
	add_child(_panel)

	# --------------- Left column — EQUIPPED ---------------
	var left_header := Label.new()
	left_header.text = "EQUIPPED"
	left_header.position = Vector2(8, 8)
	left_header.add_theme_font_size_override("font_size", 12)
	left_header.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_panel.add_child(left_header)

	var y := 28
	for slot in EQUIPPED_SLOTS:
		var label_node := Label.new()
		label_node.text = SLOT_LABELS.get(slot, slot) + ":"
		label_node.position = Vector2(8, y)
		label_node.add_theme_font_size_override("font_size", 11)
		_panel.add_child(label_node)

		var btn := Button.new()
		btn.text = "—"
		btn.position = Vector2(68, y - 2)
		btn.custom_minimum_size = Vector2(80, 20)
		btn.add_theme_font_size_override("font_size", 10)
		# Capture slot name for the callback via a wrapper array (lambda capture gotcha)
		var captured_slot := [slot]
		btn.pressed.connect(func(): _on_equipped_clicked(captured_slot[0]))
		_panel.add_child(btn)
		_equipped_buttons[slot] = btn
		y += 26

	# --------------- Right column — BAG ---------------
	var bag_header := Label.new()
	bag_header.text = "BAG"
	bag_header.position = Vector2(168, 8)
	bag_header.add_theme_font_size_override("font_size", 12)
	bag_header.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_panel.add_child(bag_header)

	for i in range(12):
		var col := i % 4
		var row := i / 4
		var btn := Button.new()
		btn.text = "—"
		btn.position = Vector2(168 + col * 38, 28 + row * 26)
		btn.custom_minimum_size = Vector2(36, 22)
		btn.add_theme_font_size_override("font_size", 9)
		var captured_i := [i]
		btn.pressed.connect(func(): _on_bag_clicked(captured_i[0]))
		_panel.add_child(btn)
		_bag_buttons.append(btn)

func _on_equipped_clicked(slot: String) -> void:
	if _player == null:
		return
	var eq = _player.get("equipment")
	if eq == null:
		return
	eq.call("unequip", slot)
	_refresh()

func _on_bag_clicked(index: int) -> void:
	if _player == null:
		return
	var eq = _player.get("equipment")
	if eq == null:
		return
	var bag: Array = eq.call("get_bag")
	if index >= bag.size():
		return
	var item_id: String = str(bag[index])
	if item_id != "":
		eq.call("equip", item_id)
	_refresh()

func _refresh() -> void:
	if _player == null:
		return
	var eq = _player.get("equipment")
	if eq == null:
		return

	# Update equipped buttons
	for slot in EQUIPPED_SLOTS:
		var item_id: String = str(eq.call("get_equipped", slot))
		var btn: Button = _equipped_buttons[slot] as Button
		btn.text = item_id if item_id != "" else "—"

	# Update bag buttons
	var bag: Array = eq.call("get_bag")
	for i in range(12):
		var btn: Button = _bag_buttons[i] as Button
		if i < bag.size():
			var item_id: String = str(bag[i])
			btn.text = item_id if item_id != "" else "—"
		else:
			btn.text = "—"
