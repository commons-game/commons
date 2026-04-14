## ShrineObject — in-world anchor that registers a shrine with ShrineTerritory.
##
## Stored in the chunk CRDT like any tile; carries extra metadata for the
## mod system and reputation layer.
##
## Lifecycle:
##   var shrine = ShrineObject.new()
##   shrine.mod_bundle_hash = "..."
##   shrine.owner_id = "player_1"
##   shrine.initialize("shrine_A", chunk_coords, territory)
##   # ... in-game lifetime ...
##   shrine.remove(territory)
class_name ShrineObject

var shrine_id: String = ""
var chunk_coords: Vector2i = Vector2i.ZERO

## Content-addressed reference to the mod bundle on the backend.
var mod_bundle_hash: String = ""
## Pinned version hash of the mod bundle.
var mod_bundle_version: String = ""
## Player who placed this shrine (reputation/reporting only — not enforced).
var owner_id: String = ""

## Call after setting metadata fields. Registers with territory immediately.
func initialize(id: String, coords: Vector2i, territory: Object) -> void:
	shrine_id   = id
	chunk_coords = coords
	territory.register_shrine(shrine_id, chunk_coords)

## Remove this shrine from the world. Dissolves its territory.
func remove(territory: Object) -> void:
	territory.unregister_shrine(shrine_id)
