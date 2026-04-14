## RemotePlayer — visual representation of a connected peer.
## No input handling. Position is driven by MultiplayerSynchronizer.
## Extends Node2D (not CharacterBody2D) so it never participates in physics.
extends Node2D

const RADIUS   := 7.0
const TRI_SIZE := 4.0

var _color: Color = Color.CYAN

func _enter_tree() -> void:
	# Both authority and replication config must be set in _enter_tree so the
	# MultiplayerSynchronizer gets a valid network ID before on_replication_start fires.
	# Setting them in _ready is too late — the spawner processes replication during enter_tree.
	var parts := name.split("_")
	if parts.size() == 2 and parts[1].is_valid_int():
		var peer_id := int(parts[1])
		set_multiplayer_authority(peer_id)
		_color = _color_for_peer(peer_id)
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.property_set_spawn(NodePath(".:position"), true)
	config.property_set_sync(NodePath(".:position"), true)
	$MultiplayerSynchronizer.replication_config = config

func _ready() -> void:
	pass

func _draw() -> void:
	# Body: peer-colored filled circle with dark outline
	draw_circle(Vector2.ZERO, RADIUS, Color(0.1, 0.1, 0.1))       # outline
	draw_circle(Vector2.ZERO, RADIUS - 1.0, _color)
	# Direction marker: fixed upward triangle (remote players don't send facing)
	var tip   := Vector2.UP * (RADIUS + TRI_SIZE)
	var left  := Vector2.UP.rotated(deg_to_rad( 140.0)) * (TRI_SIZE * 0.8)
	var right := Vector2.UP.rotated(deg_to_rad(-140.0)) * (TRI_SIZE * 0.8)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.9, 0.7, 0.1))

func _process(_delta: float) -> void:
	queue_redraw()

## Derive a visually distinct hue from peer_id using golden-ratio spacing.
static func _color_for_peer(peer_id: int) -> Color:
	# Peer 1 (host) → cyan; others spread around the hue wheel.
	if peer_id == 1:
		return Color.CYAN
	var hue := fmod((peer_id * 0.618033988749895), 1.0)
	return Color.from_hsv(hue, 0.75, 0.95)
