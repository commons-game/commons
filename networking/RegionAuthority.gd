## RegionAuthority — determines which peer holds Godot multiplayer authority
## for each chunk, based on proximity.
##
## Authority for a chunk is the registered peer whose current chunk position
## is closest (Chebyshev distance). Ties broken by lowest peer_id.
## If no peers are registered, LOCAL_PEER_ID (1) owns everything.
##
## Callers must keep positions current via on_peer_moved() and clean up
## via on_peer_left(). The local peer should register itself too.
class_name RegionAuthority

const LOCAL_PEER_ID := 1

# peer_id (int) -> Vector2i chunk position
var _positions: Dictionary = {}

## Register or update a peer's chunk position.
func on_peer_moved(peer_id: int, chunk: Vector2i) -> void:
	_positions[peer_id] = chunk

## Remove a peer; authority redistributes automatically on next query.
func on_peer_left(peer_id: int) -> void:
	_positions.erase(peer_id)

## Returns the peer_id that holds authority for the given chunk.
func get_authority_for_chunk(coords: Vector2i) -> int:
	if _positions.is_empty():
		return LOCAL_PEER_ID

	var best_id := LOCAL_PEER_ID
	var best_dist := INF

	for peer_id in _positions:
		var pos: Vector2i = _positions[peer_id]
		var dist := _chebyshev(pos, coords)
		# Strictly less-than: lowest peer_id wins ties
		if dist < best_dist or (dist == best_dist and peer_id < best_id):
			best_dist = dist
			best_id = peer_id

	return best_id

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
