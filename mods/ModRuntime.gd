## ModRuntime — stateless trigger evaluator.
## Given a tile id, a trigger context, and a ModBundle, returns the list of
## EffectDef objects that should fire. Caller applies them.
##
## Trigger context dict shape:
##   { "trigger": String, "entity_tags": Array[String], ...extra }
##
## Only conditions the runtime currently evaluates:
##   has_tag(tag)       — entity_tags contains tag
##   random(probability) — randf() < probability
## Unknown condition types default to TRUE (permissive — don't silently swallow effects).
class_name ModRuntime

func get_effects(tile_id: String, ctx: Dictionary, bundle: Object) -> Array:
	if not bundle.tile_defs.has(tile_id):
		return []
	var tile_def = bundle.tile_defs[tile_id]
	var trigger: String = ctx.get("trigger", "")
	var handlers: Array = _handlers_for_trigger(tile_def, trigger)
	var results := []
	for handler in handlers:
		if _condition_passes(handler.condition, ctx):
			results.append_array(handler.effects)
	return results

func _handlers_for_trigger(tile_def: Object, trigger: String) -> Array:
	match trigger:
		"on_walk":     return tile_def.on_walk
		"on_place":    return tile_def.on_place
		"on_remove":   return tile_def.on_remove
		"on_proximity": return tile_def.on_proximity
		_:             return []

func _condition_passes(condition, ctx: Dictionary) -> bool:
	if condition == null:
		return true
	match condition.type:
		"has_tag":
			var required_tag: String = condition.params.get("tag", "")
			return (ctx.get("entity_tags", []) as Array).has(required_tag)
		"random":
			var prob: float = float(condition.params.get("probability", 1.0))
			return randf() < prob
		_:
			push_warning("ModRuntime: unknown condition type '%s' — defaulting to true" \
				% condition.type)
			return true
