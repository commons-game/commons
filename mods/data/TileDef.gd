## TileDef — definition of a custom tile type in a mod bundle.
class_name TileDef

const EventHandlerScript := preload("res://mods/data/EventHandler.gd")

var id: String = ""
var solid: bool = false
var passable_by: Array = []   # Array[String] — entity tags that ignore solid
var tags: Array = []          # Array[String]
var decay_rate: float = 1.0
var on_place: Array = []      # Array[EventHandler]
var on_remove: Array = []     # Array[EventHandler]
var on_walk: Array = []       # Array[EventHandler]
var on_proximity: Array = []  # Array[EventHandler] (each may carry a radius param)

func parse(d: Dictionary) -> void:
	id = d.get("id", "")
	solid = d.get("solid", false)
	passable_by = d.get("passable_by", []).duplicate()
	tags = d.get("tags", []).duplicate()
	decay_rate = float(d.get("decay_rate", 1.0))
	on_place = _parse_handlers(d.get("on_place", []))
	on_remove = _parse_handlers(d.get("on_remove", []))
	on_walk = _parse_handlers(d.get("on_walk", []))
	on_proximity = _parse_handlers(d.get("on_proximity", []))

func _parse_handlers(arr: Array) -> Array:
	var result := []
	for item in arr:
		var h = EventHandlerScript.new()
		h.parse(item)
		result.append(h)
	return result
