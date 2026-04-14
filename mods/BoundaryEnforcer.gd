## BoundaryEnforcer — vampire rule for shrine-bound entities.
##
## An entity with a non-empty origin_shrine is safe only while inside a chunk
## owned by that shrine. Any other chunk (wilderness, contested, or a different
## shrine) triggers boundary damage scaled by delta.
## When health drops to or below zero, die_at_boundary() is called on the entity.
##
## Expected entity interface:
##   var origin_shrine: String
##   var health: float
##   func apply_boundary_damage(amount: float) -> void
##   func die_at_boundary() -> void
##
## Usage:
##   enforcer.territory = my_shrine_territory
##   enforcer.damage_per_tick = 10.0
##   enforcer.on_entity_moved(entity, new_chunk, delta)
class_name BoundaryEnforcer

var territory: Object = null   # ShrineTerritory
var damage_per_tick: float = 10.0

func on_entity_moved(entity: Object, new_chunk: Vector2i, delta: float) -> void:
	var origin: String = entity.origin_shrine
	# Neutral / player entities have no shrine affiliation — always safe.
	if origin == "":
		return

	var owner = territory.get_shrine_for_chunk(new_chunk)
	if owner == origin:
		return  # safe inside own territory

	# Outside own territory — apply damage
	var damage := damage_per_tick * delta
	entity.apply_boundary_damage(damage)
	if entity.health <= 0.0:
		entity.die_at_boundary()
