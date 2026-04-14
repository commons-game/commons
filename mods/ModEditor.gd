## ModEditor — in-game overlay for authoring and publishing mod bundles.
##
## Toggle with Tab. Shows a TextEdit pre-filled with a JSON mod template.
## "Publish Shrine Here" stores the bundle and places a shrine at the player's chunk.
##
## Wired by World._ready():
##   $ModEditor.shrine_manager = $ShrineManager
##   $ModEditor.player         = $Player
extends CanvasLayer

const ShrineManagerScript := preload("res://mods/ShrineManager.gd")

const TEMPLATE := """{
  "tiles": [],
  "buffs": [
    {
      "id": "shrine_haste",
      "label": "Shrine Haste",
      "description": "Movement speed boost granted inside shrine territory"
    }
  ]
}"""

var shrine_manager: ShrineManagerScript = null  # set by World
var player: Node2D = null                       # set by World

var _panel: Panel
var _text_edit: TextEdit
var _status_label: Label
var _visible := false

func _ready() -> void:
	layer = 10
	_build_ui()
	hide()

func _build_ui() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(480, 360)
	_panel.position = Vector2(-240, -180)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Mod Editor  [F2 to close]"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	var instructions := Label.new()
	instructions.text = "Edit the JSON below, then click Publish to place a shrine\nat your current chunk and load this mod bundle."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(instructions)

	_text_edit = TextEdit.new()
	_text_edit.text = TEMPLATE
	_text_edit.custom_minimum_size = Vector2(0, 220)
	_text_edit.syntax_highlighter = null  # plain text is fine
	vbox.add_child(_text_edit)

	var btn := Button.new()
	btn.text = "Publish Shrine Here"
	btn.pressed.connect(_on_publish)
	vbox.add_child(btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	vbox.add_child(_status_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	_visible = !_visible
	if _visible:
		show()
	else:
		hide()

func _on_publish() -> void:
	if shrine_manager == null or player == null:
		_status("ERROR: shrine_manager or player not wired")
		return
	var json_text := _text_edit.text.strip_edges()
	if json_text.is_empty():
		_status("ERROR: JSON is empty")
		return
	# Validate JSON before sending
	var test = JSON.parse_string(json_text)
	if test == null:
		_status("ERROR: invalid JSON — check syntax")
		return
	var tile_pos := Vector2i(
		int(floorf(player.position.x / Constants.TILE_SIZE)),
		int(floorf(player.position.y / Constants.TILE_SIZE))
	)
	var shrine_id := shrine_manager.place_shrine(tile_pos, json_text, PlayerIdentity.id)
	if shrine_id.is_empty():
		_status("ERROR: place_shrine returned empty id")
	else:
		var chunk := CoordUtils.world_to_chunk(tile_pos)
		_status("Shrine published at chunk %s\nWalk in to activate." % chunk)

func _status(msg: String) -> void:
	_status_label.text = msg
