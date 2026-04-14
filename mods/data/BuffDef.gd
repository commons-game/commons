## BuffDef — definition of a named status buff in a mod bundle.
class_name BuffDef

var id: String = ""
var speed_modifier: float = 1.0
var damage_modifier: float = 1.0
var defense_modifier: float = 1.0
var merge_pressure_multiplier: float = 1.0
var duration: float = -1.0   # -1 = permanent until removed

func parse(d: Dictionary) -> void:
	id = d.get("id", "")
	speed_modifier = float(d.get("speed_modifier", 1.0))
	damage_modifier = float(d.get("damage_modifier", 1.0))
	defense_modifier = float(d.get("defense_modifier", 1.0))
	merge_pressure_multiplier = float(d.get("merge_pressure_multiplier", 1.0))
	duration = float(d.get("duration", -1.0))
