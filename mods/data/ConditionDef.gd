## ConditionDef — a single optional filter on an event handler.
## type: String identifier ("has_tag", "has_item", "random", etc.)
## params: Dictionary of type-specific parameters.
class_name ConditionDef

var type: String = ""
var params: Dictionary = {}

func parse(d: Dictionary) -> void:
	type = d.get("type", "")
	for key in d:
		if key != "type":
			params[key] = d[key]
