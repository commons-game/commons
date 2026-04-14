## Tests for LocalPresenceService — in-memory presence publish/subscribe.
## Simulates the backend presence layer for LAN/testing (LocalBackend).
##
## Rules:
##   - publish_presence() stores the player's position and fires callbacks
##     for any subscriber whose area contains the published chunk.
##   - subscribe_area() registers a callback for a center + radius area.
##   - unsubscribe_area() removes the subscription; no further callbacks.
##   - Radius uses Chebyshev distance (same as RegionAuthority).
##   - Publishing your own position does not fire your own subscription.
extends GdUnitTestSuite

const LocalPresenceServiceScript := preload("res://networking/LocalPresenceService.gd")

func _make_service() -> Object:
	return LocalPresenceServiceScript.new()

# --- publish fires matching subscriber ---

func test_publish_fires_subscriber_in_range() -> void:
	var svc = _make_service()
	var received: Array = []
	svc.subscribe_area("watcher", Vector2i(0, 0), 5,
		func(pid, coords): received.append({"pid": pid, "coords": coords}))

	svc.publish_presence("player_2", Vector2i(3, 3))
	assert_that(received.size()).is_equal(1)
	assert_that(received[0]["pid"]).is_equal("player_2")
	assert_that(received[0]["coords"]).is_equal(Vector2i(3, 3))

func test_publish_does_not_fire_out_of_range_subscriber() -> void:
	var svc = _make_service()
	var received: Array = []
	svc.subscribe_area("watcher", Vector2i(0, 0), 2,
		func(pid, _c): received.append(pid))

	svc.publish_presence("player_2", Vector2i(10, 10))
	assert_that(received.size()).is_equal(0)

func test_publish_fires_boundary_subscriber_exactly_at_radius() -> void:
	var svc = _make_service()
	var received: Array = []
	svc.subscribe_area("watcher", Vector2i(0, 0), 3,
		func(pid, _c): received.append(pid))

	# Chebyshev distance from (0,0) to (3,0) is exactly 3 — within radius
	svc.publish_presence("player_2", Vector2i(3, 0))
	assert_that(received.size()).is_equal(1)

func test_publish_does_not_fire_subscriber_one_beyond_radius() -> void:
	var svc = _make_service()
	var received: Array = []
	svc.subscribe_area("watcher", Vector2i(0, 0), 3,
		func(pid, _c): received.append(pid))

	svc.publish_presence("player_2", Vector2i(4, 0))
	assert_that(received.size()).is_equal(0)

# --- own publish does not fire own subscription ---

func test_own_publish_does_not_fire_own_subscription() -> void:
	var svc = _make_service()
	var received: Array = []
	svc.subscribe_area("player_1", Vector2i(0, 0), 10,
		func(pid, _c): received.append(pid))

	svc.publish_presence("player_1", Vector2i(0, 0))
	assert_that(received.size()).is_equal(0)

# --- multiple subscribers ---

func test_multiple_subscribers_all_fired() -> void:
	var svc = _make_service()
	var a: Array = []
	var b: Array = []
	svc.subscribe_area("watcher_a", Vector2i(0, 0), 5, func(p, _c): a.append(p))
	svc.subscribe_area("watcher_b", Vector2i(0, 0), 5, func(p, _c): b.append(p))

	svc.publish_presence("player_3", Vector2i(1, 0))
	assert_that(a.size()).is_equal(1)
	assert_that(b.size()).is_equal(1)

# --- unsubscribe ---

func test_unsubscribe_stops_callbacks() -> void:
	var svc = _make_service()
	var received: Array = []
	svc.subscribe_area("watcher", Vector2i(0, 0), 5, func(p, _c): received.append(p))
	svc.unsubscribe_area("watcher")
	svc.publish_presence("player_2", Vector2i(1, 0))
	assert_that(received.size()).is_equal(0)

func test_unsubscribe_unknown_id_no_crash() -> void:
	var svc = _make_service()
	svc.unsubscribe_area("nobody")  # should not crash

# --- get_presence ---

func test_get_presence_returns_published_position() -> void:
	var svc = _make_service()
	svc.publish_presence("player_1", Vector2i(4, 7))
	assert_that(svc.get_presence("player_1")).is_equal(Vector2i(4, 7))

func test_get_presence_unknown_player_returns_null() -> void:
	var svc = _make_service()
	assert_that(svc.get_presence("ghost")).is_null()
