## LocalPresenceService — in-memory presence publish/subscribe.
## Simulates the backend presence layer for LAN and headless testing.
## (FreenetBackend will implement the same contract via Freenet area contracts.)
##
## Radius uses Chebyshev distance, matching RegionAuthority.
## A player's own publish_presence never fires their own subscription.
class_name LocalPresenceService

# subscriber_id -> {center, radius, callback}
var _subscriptions: Dictionary = {}

# player_id -> Vector2i
var _presences: Dictionary = {}

func publish_presence(player_id: String, chunk_coords: Vector2i) -> void:
	_presences[player_id] = chunk_coords
	for sub_id in _subscriptions:
		if sub_id == player_id:
			continue  # don't fire own subscription
		var sub: Dictionary = _subscriptions[sub_id]
		var dist := _chebyshev(sub["center"] as Vector2i, chunk_coords)
		if dist <= sub["radius"]:
			(sub["callback"] as Callable).call(player_id, chunk_coords)

func subscribe_area(subscriber_id: String, center: Vector2i,
		radius: int, callback: Callable) -> void:
	_subscriptions[subscriber_id] = {
		"center": center, "radius": radius, "callback": callback
	}

func unsubscribe_area(subscriber_id: String) -> void:
	_subscriptions.erase(subscriber_id)

## Returns the last published position for a player, or null if unknown.
func get_presence(player_id: String):
	return _presences.get(player_id, null)

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
