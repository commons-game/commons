## MergePressureSystem — solo-time pressure accumulator.
##
## pressure ticks up at ramp_rate per second while peer_count == 1 (solo).
## Capped at 1.0. reset() drops to reset_value (small positive residual,
## not zero — a player who just merged still has some pull toward meeting others).
## apply_talisman_modifier() scales ramp_rate multiplicatively.
##
## Callers must set peer_count each frame and call tick(delta).
class_name MergePressureSystem

var pressure: float = 0.0
var ramp_rate: float = 0.001   # per second
var reset_value: float = 0.05  # pressure after merge/split

var peer_count: int = 1        # caller keeps this current

func tick(delta: float) -> void:
	if peer_count > 1:
		return
	pressure = minf(1.0, pressure + ramp_rate * delta)

func reset() -> void:
	pressure = reset_value

func apply_talisman_modifier(modifier: float) -> void:
	ramp_rate *= modifier
