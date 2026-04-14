## SplitDetector — monitors bridge, triggers dissolution when sessions drift apart.
##
## should_dissolve() uses Chebyshev distance. When it returns true, call
## on_dissolve() to reset the pressure system and clear the bridge.
class_name SplitDetector

const SPLIT_DISTANCE := 25   # Chebyshev chunks

func should_dissolve(pos_a: Vector2i, pos_b: Vector2i) -> bool:
	return _chebyshev(pos_a, pos_b) > SPLIT_DISTANCE

## Reset the merge pressure system after a split. Safe to call with null.
func on_dissolve(pressure_system) -> void:
	if pressure_system == null:
		return
	pressure_system.reset()

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
