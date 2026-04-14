## BridgeFormation — determines when and where bridge chunks appear between sessions.
##
## should_form_bridge(): both sessions must be within BRIDGE_MAX_DISTANCE chunks
## (Chebyshev) AND both pressures must pass a probability gate (randf() < pressure).
## With pressure=1.0 the gate always passes; 0.0 never passes.
##
## get_bridge_chunks(): returns the straight-line intermediate chunks between
## two session positions using integer linear interpolation. Excludes endpoints.
class_name BridgeFormation

const BRIDGE_MAX_DISTANCE := 20   # Chebyshev chunks

func should_form_bridge(pos_a: Vector2i, pos_b: Vector2i,
		pressure_a: float, pressure_b: float) -> bool:
	if _chebyshev(pos_a, pos_b) > BRIDGE_MAX_DISTANCE:
		return false
	# Both pressures must independently pass the gate.
	if not (randf() < pressure_a):
		return false
	if not (randf() < pressure_b):
		return false
	return true

## Returns the intermediate chunks on the straight-line path from pos_a to pos_b,
## excluding both endpoints. Returns empty if the positions are adjacent or identical.
func get_bridge_chunks(pos_a: Vector2i, pos_b: Vector2i) -> Array:
	var steps := maxi(absi(pos_b.x - pos_a.x), absi(pos_b.y - pos_a.y))
	if steps <= 1:
		return []
	var result: Array = []
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var x := roundi(lerp(float(pos_a.x), float(pos_b.x), t))
		var y := roundi(lerp(float(pos_a.y), float(pos_b.y), t))
		result.append(Vector2i(x, y))
	return result

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
