## BuffManager — tracks active buffs on an entity and evicts them on shrine boundary crossing.
##
## Each buff entry records the buff_id and origin_shrine that granted it.
## On on_chunk_changed(new_chunk):
##   - Buffs whose origin_shrine doesn't match the new chunk's shrine are removed.
##   - Buffs with origin_shrine == "" (origin-less / baseline) are never evicted.
##
## Usage:
##   manager.territory = my_shrine_territory
##   manager.add_buff("speed_up", "shrine_A")
##   manager.on_chunk_changed(new_chunk)
##   var buffs := manager.get_buffs()  # Array of { buff_id, origin_shrine }
class_name BuffManager

var territory: Object = null  # ShrineTerritory

# Array of Dictionaries: { "buff_id": String, "origin_shrine": String }
var _buffs: Array = []

func add_buff(buff_id: String, origin_shrine: String) -> void:
	_buffs.append({"buff_id": buff_id, "origin_shrine": origin_shrine})

func get_buffs() -> Array:
	return _buffs.duplicate()

func on_chunk_changed(new_chunk: Vector2i) -> void:
	var current_shrine = territory.get_shrine_for_chunk(new_chunk)  # String or null
	_buffs = _buffs.filter(func(entry: Dictionary) -> bool:
		var origin: String = entry["origin_shrine"]
		# Origin-less buffs are never evicted.
		if origin == "":
			return true
		# Keep buff only if the current chunk belongs to the same shrine.
		return origin == current_shrine
	)
