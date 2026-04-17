## Tether — placeable structure that anchors the player's home spawn.
##
## Visual: a pale blue/white crystalline spike (Still) wrapped by a slow-pulsing
## green organic tendril (Bloom). Small footprint (~8-10px radius).
##
## Mechanics:
##   - owner_id must be set immediately after instantiation.
##   - hp = 50; immune to bare hands — requires flint_knife to damage.
##   - On hp <= 0: emits tether_broken(owner_id) and queue_frees itself.
##   - take_damage(amount, tool_id) returns false and prints "Need a tool"
##     if tool_id is not "flint_knife".
##   - On _ready: registers with TetherRegistry (removing any previous Tether
##     for this owner). On predelete: unregisters.
##
## One per player. Player.gd is responsible for setting home_pos on placement.
extends Node2D

## Emitted when the Tether's HP reaches zero.
signal tether_broken(owner_id: String)

## The PlayerIdentity.id of the player who placed this Tether.
var owner_id: String = ""

## Hit points. Reduced only by flint_knife or better.
var hp: int = 50

## Visual animation state.
var _anim_time: float = 0.0

func _ready() -> void:
	z_index = 2
	if owner_id != "":
		TetherRegistry.register_tether(owner_id, self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if owner_id != "":
			TetherRegistry.unregister_tether(owner_id)

func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()

## Apply damage to this Tether.
## attacker_tool: the id string of the tool being used (e.g. "flint_knife").
## Returns false if the tool is insufficient (bare hands), true if damage was applied.
func take_damage(amount: int, attacker_tool: String) -> bool:
	if attacker_tool != "flint_knife":
		print("Tether: Need a tool to damage this.")
		return false
	hp = max(0, hp - amount)
	print("Tether: took %d damage, hp=%d" % [amount, hp])
	if hp <= 0:
		emit_signal("tether_broken", owner_id)
		queue_free()
	return true

func _draw() -> void:
	# -----------------------------------------------------------------------
	# Still — crystalline spike: pale blue/white angular shard pointing up.
	# -----------------------------------------------------------------------
	# Outer glow (soft blue haze)
	draw_circle(Vector2.ZERO, 10.0, Color(0.55, 0.75, 1.0, 0.18))

	# Crystal body: a narrow diamond polygon
	var crystal := PackedVector2Array([
		Vector2(0.0, -10.0),   # tip (top)
		Vector2(4.0,  -3.0),   # right shoulder
		Vector2(3.0,   4.0),   # right base
		Vector2(0.0,   5.5),   # bottom
		Vector2(-3.0,  4.0),   # left base
		Vector2(-4.0, -3.0),   # left shoulder
	])
	draw_colored_polygon(crystal, Color(0.82, 0.93, 1.0, 0.92))

	# Inner highlight facet (slightly offset left — light catching)
	var facet := PackedVector2Array([
		Vector2(-1.0, -9.0),
		Vector2( 1.5, -4.0),
		Vector2(-1.5, -2.0),
		Vector2(-3.5, -4.5),
	])
	draw_colored_polygon(facet, Color(1.0, 1.0, 1.0, 0.55))

	# Thin outline to crisp the edges
	for i in range(crystal.size()):
		var a: Vector2 = crystal[i]
		var b: Vector2 = crystal[(i + 1) % crystal.size()]
		draw_line(a, b, Color(0.45, 0.65, 0.95, 0.8), 1.0)

	# -----------------------------------------------------------------------
	# Bloom — organic tendril: slow pulsing green ring around the base.
	# -----------------------------------------------------------------------
	var pulse: float = sin(_anim_time * 1.8) * 0.5 + 0.5   # 0..1, slow
	var tendril_r: float = 6.0 + pulse * 2.5                # 6..8.5 px radius
	var tendril_w: float = 1.5 + pulse * 1.0                # 1.5..2.5 px thickness
	var tendril_alpha: float = 0.55 + pulse * 0.3           # 0.55..0.85

	# Draw the tendril as a series of arc segments (approximate circle via polyline)
	var seg_count := 20
	var prev_pt: Vector2 = Vector2.ZERO
	for i in range(seg_count + 1):
		var angle: float = (float(i) / seg_count) * TAU + _anim_time * 0.4
		var pt := Vector2(cos(angle) * tendril_r, sin(angle) * tendril_r + 3.0)
		if i > 0:
			draw_line(prev_pt, pt, Color(0.2, 0.85, 0.35, tendril_alpha), tendril_w)
		prev_pt = pt

	# Small organic knobs at three evenly-spaced points on the tendril
	for k in range(3):
		var knob_angle: float = (float(k) / 3.0) * TAU + _anim_time * 0.4
		var knob_pos := Vector2(cos(knob_angle) * tendril_r, sin(knob_angle) * tendril_r + 3.0)
		draw_circle(knob_pos, tendril_w * 0.9, Color(0.15, 0.7, 0.25, tendril_alpha))
