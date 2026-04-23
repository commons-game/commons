## Tether — placeable structure. Each player treats their own last-placed
## Tether tile as their home-spawn anchor; that relationship lives on the
## Player (Player._home_tile_pos) — the tile itself has no owner.
##
## Visual: a pale blue/white crystalline spike (Still) wrapped by a slow-pulsing
## green organic tendril (Bloom). Small footprint (~8-10px radius).
##
## Mechanics:
##   - hp = 50; immune to bare hands — requires flint_knife to damage.
##   - On hp <= 0: requests the tile be removed via TileMutationBus. The bus
##     fires tile_removed, ChunkManager._despawn_structure_at frees this node,
##     and any Player whose _home_tile_pos matches this tile discovers their
##     Tether is gone.
##   - Registers with TetherRegistry keyed by world_tile_pos (not owner_id).
##
## One per player — but enforcement is local (Player replaces _home_tile_pos
## on each new placement). The world itself allows any number of Tethers.
extends Node2D

## World-tile position. Set by ChunkManager when spawning from CRDT.
var world_tile_pos: Vector2i = Vector2i.ZERO

## Hit points. Reduced only by flint_knife or better.
var hp: int = 50

## Visual animation state.
var _anim_time: float = 0.0

func _ready() -> void:
	z_index = 2
	TetherRegistry.register_tether(world_tile_pos, self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		TetherRegistry.unregister_tether(world_tile_pos)

func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()

## Apply damage to this Tether.
## attacker_tool: the id string of the tool being used (e.g. "flint_knife").
## Returns false if the tool is insufficient, true if damage was applied.
func take_damage(amount: int, attacker_tool: String) -> bool:
	if attacker_tool != "flint_knife":
		print("Tether: Need a tool to damage this.")
		return false
	hp = max(0, hp - amount)
	print("Tether: took %d damage, hp=%d" % [amount, hp])
	if hp <= 0:
		# Remove the CRDT tile — ChunkManager frees this scene in response.
		var bus: Node = get_tree().root.find_child("TileMutationBus", true, false)
		if bus != null:
			bus.request_remove_tile(world_tile_pos, 1)
		else:
			# Fallback: scene-only kill (shouldn't happen in a real game, but
			# keeps unit tests that instantiate Tether in isolation from crashing).
			queue_free()
	return true

func _draw() -> void:
	draw_circle(Vector2.ZERO, 10.0, Color(0.55, 0.75, 1.0, 0.18))

	var crystal := PackedVector2Array([
		Vector2(0.0, -10.0),
		Vector2(4.0,  -3.0),
		Vector2(3.0,   4.0),
		Vector2(0.0,   5.5),
		Vector2(-3.0,  4.0),
		Vector2(-4.0, -3.0),
	])
	draw_colored_polygon(crystal, Color(0.82, 0.93, 1.0, 0.92))

	var facet := PackedVector2Array([
		Vector2(-1.0, -9.0),
		Vector2( 1.5, -4.0),
		Vector2(-1.5, -2.0),
		Vector2(-3.5, -4.5),
	])
	draw_colored_polygon(facet, Color(1.0, 1.0, 1.0, 0.55))

	for i in range(crystal.size()):
		var a: Vector2 = crystal[i]
		var b: Vector2 = crystal[(i + 1) % crystal.size()]
		draw_line(a, b, Color(0.45, 0.65, 0.95, 0.8), 1.0)

	var pulse: float = sin(_anim_time * 1.8) * 0.5 + 0.5
	var tendril_r: float = 6.0 + pulse * 2.5
	var tendril_w: float = 1.5 + pulse * 1.0
	var tendril_alpha: float = 0.55 + pulse * 0.3

	var seg_count := 20
	var prev_pt: Vector2 = Vector2.ZERO
	for i in range(seg_count + 1):
		var angle: float = (float(i) / seg_count) * TAU + _anim_time * 0.4
		var pt := Vector2(cos(angle) * tendril_r, sin(angle) * tendril_r + 3.0)
		if i > 0:
			draw_line(prev_pt, pt, Color(0.2, 0.85, 0.35, tendril_alpha), tendril_w)
		prev_pt = pt

	for k in range(3):
		var knob_angle: float = (float(k) / 3.0) * TAU + _anim_time * 0.4
		var knob_pos := Vector2(cos(knob_angle) * tendril_r, sin(knob_angle) * tendril_r + 3.0)
		draw_circle(knob_pos, tendril_w * 0.9, Color(0.15, 0.7, 0.25, tendril_alpha))
