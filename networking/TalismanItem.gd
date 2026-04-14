## TalismanItem — in-game item carrying a merge_pressure_modifier.
## Applying a talisman multiplies MergePressureSystem.ramp_rate by modifier.
## Multiple talismans stack multiplicatively.
class_name TalismanItem

var id: String = ""
var modifier: float = 1.0

## Apply this talisman's modifier to a MergePressureSystem.
func apply_to(pressure_system: Object) -> void:
	pressure_system.apply_talisman_modifier(modifier)
