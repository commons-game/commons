## RemotePlayer — visual representation of a connected peer.
## No input handling. Position is driven by MultiplayerSynchronizer.
## Extends Node2D (not CharacterBody2D) so it never participates in physics.
##
## Appearance is synced via eight replicated properties:
##   appearance_base_body_id, appearance_held_item_id,
##   appearance_facing_x, appearance_facing_y, appearance_walk_frame,
##   appearance_armor_id, appearance_head_id, appearance_feet_id
## The local Player pushes these to its own RemotePlayer node each physics tick,
## and the MultiplayerSynchronizer replicates them to all peers.
extends Node2D

const CharacterAppearanceScript := preload("res://player/CharacterAppearance.gd")
const CharacterRendererScript   := preload("res://player/CharacterRenderer.gd")

const RADIUS   := 7.0
const TRI_SIZE := 4.0

## Peer-derived color used by the draw-code fallback.
var _color: Color = Color.CYAN

## Synced appearance state — written by the authoritative peer's Player node,
## replicated to all others by MultiplayerSynchronizer.
var appearance_base_body_id:  String = "default"
var appearance_held_item_id:  String = ""
var appearance_facing_x:      float  = 0.0
var appearance_facing_y:      float  = -1.0
var appearance_walk_frame:    int    = 0
var appearance_armor_id:      String = ""
var appearance_head_id:       String = ""
var appearance_feet_id:       String = ""

var _appearance = null  # CharacterAppearance
var _renderer   = null  # CharacterRenderer

func _enter_tree() -> void:
	# Authority + replication config must be set in _enter_tree so the
	# MultiplayerSynchronizer gets a valid network ID before on_replication_start fires.
	var parts := name.split("_")
	if parts.size() == 2 and parts[1].is_valid_int():
		var peer_id := int(parts[1])
		set_multiplayer_authority(peer_id)
		_color = _color_for_peer(peer_id)

	var config := SceneReplicationConfig.new()
	# Position
	config.add_property(NodePath(".:position"))
	config.property_set_spawn(NodePath(".:position"), true)
	config.property_set_sync(NodePath(".:position"), true)
	# Appearance — all 8 vars
	for prop in [
		".:appearance_base_body_id",
		".:appearance_held_item_id",
		".:appearance_facing_x",
		".:appearance_facing_y",
		".:appearance_walk_frame",
		".:appearance_armor_id",
		".:appearance_head_id",
		".:appearance_feet_id",
	]:
		config.add_property(NodePath(prop))
		config.property_set_spawn(NodePath(prop), true)
		config.property_set_sync(NodePath(prop), true)
	$MultiplayerSynchronizer.replication_config = config

func _ready() -> void:
	z_index = 2  # render above tile layers, same as Player
	_appearance = CharacterAppearanceScript.new()
	_renderer   = CharacterRendererScript.new()
	_renderer.name = "CharacterRenderer"
	add_child(_renderer)

func _process(_delta: float) -> void:
	# Rebuild appearance from synced vars and refresh the renderer.
	if _appearance != null and _renderer != null:
		_appearance.base_body_id  = appearance_base_body_id
		_appearance.held_item_id  = appearance_held_item_id
		_appearance.facing        = Vector2(appearance_facing_x, appearance_facing_y)
		_appearance.walk_frame    = appearance_walk_frame
		_appearance.armor_id      = appearance_armor_id
		_appearance.head_id       = appearance_head_id
		_appearance.feet_id       = appearance_feet_id
		_renderer.refresh(_appearance)
	queue_redraw()

func _draw() -> void:
	# Suppress draw-code when CharacterRenderer has sprites showing.
	if _renderer != null and _renderer.has_visible_sprites():
		return
	# Fallback: peer-colored circle + fixed upward direction marker.
	draw_circle(Vector2.ZERO, RADIUS, Color(0.1, 0.1, 0.1))
	draw_circle(Vector2.ZERO, RADIUS - 1.0, _color)
	var tip   := Vector2.UP * (RADIUS + TRI_SIZE)
	var left  := Vector2.UP.rotated(deg_to_rad( 140.0)) * (TRI_SIZE * 0.8)
	var right := Vector2.UP.rotated(deg_to_rad(-140.0)) * (TRI_SIZE * 0.8)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.9, 0.7, 0.1))

## Derive a visually distinct hue from peer_id using golden-ratio spacing.
static func _color_for_peer(peer_id: int) -> Color:
	if peer_id == 1:
		return Color.CYAN
	var hue := fmod((peer_id * 0.618033988749895), 1.0)
	return Color.from_hsv(hue, 0.75, 0.95)
