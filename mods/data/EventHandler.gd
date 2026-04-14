## EventHandler — one (condition, effects[]) pair on a trigger.
## condition is null when there is no filter.
class_name EventHandler

const ConditionDefScript := preload("res://mods/data/ConditionDef.gd")
const EffectDefScript := preload("res://mods/data/EffectDef.gd")

var condition  # ConditionDef or null
var effects: Array = []  # Array[EffectDef]

func parse(d: Dictionary) -> void:
	if d.has("condition") and d["condition"] != null:
		condition = ConditionDefScript.new()
		condition.parse(d["condition"])
	else:
		condition = null
	for effect_dict in d.get("effects", []):
		var e = EffectDefScript.new()
		e.parse(effect_dict)
		effects.append(e)
