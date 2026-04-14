## EffectDef — a single effect within an event handler.
## type: String identifier ("deal_damage", "apply_buff", "spawn_entity", etc.)
## params: Dictionary of type-specific parameters.
class_name EffectDef

var type: String = ""
var params: Dictionary = {}

func parse(d: Dictionary) -> void:
	type = d.get("type", "")
	for key in d:
		if key != "type":
			params[key] = d[key]
