## TileInteraction — mouse-driven tile interaction, tool-aware.
##
## Active tool (from Player.inventory.get_active_tool()) determines behavior:
##
##   shovel
##     Left click  : dig ground tile (layer 0), adds 1 "dirt" to bag.
##     Right click : place "dirt" tile on ground layer if bag has dirt.
##
##   campfire / workbench (structure items)
##     Right click : place structure tile on object layer (layer 1) at the
##                   clicked tile position if it is empty. Removes the item
##                   from the active tool slot.
##
##   wooden_axe / wooden_pickaxe / stone_axe / stone_pickaxe / fist (no tool)
##     Left click  : swing at object-layer tile (tree/rock).
##                   wooden_axe: 2 vs trees, 1 vs rocks.
##                   wooden_pickaxe: 2 vs rocks, 1 vs trees.
##                   stone_axe: 3 vs trees, 1 vs rocks.
##                   stone_pickaxe: 3 vs rocks, 1 vs trees.
##                   Fist deals 1 damage to either.
##                   On tile death: removes tile via CRDT, drops resources into bag.
##                   Ephemeral damage resets after DAMAGE_RESET_S of inactivity.
##
## Visual feedback (no art assets required):
##   Hit     → brief white flash over tile (TileHitFlash node)
##   Last HP → red flash that lingers 0.8s
##   Death   → CPUParticles2D debris burst, colour-coded by tile type
##
## Audio stub: _play_hit_sound() is silent until .ogg assets are wired up.
extends Node

## Structure item IDs that can be placed in the world via right-click.
## Key: item id → tile_id string used with TileMutationBus.request_place_tile()
const STRUCTURE_TILES := {
	"campfire":  "campfire",
	"workbench": "workbench",
}

const DIG_RANGE_TILES := 5
const DAMAGE_RESET_S  := 2.0  # inactivity window before ephemeral HP resets

const TileHitFlashScript := preload("res://player/TileHitFlash.gd")

## Object-layer tiles that can be harvested.
## Key: atlas coords (Vector2i). Value: {max_hp, drops: Array of {id, category, min, max}}
const HARVESTABLE_TILES := {
	Vector2i(0, 1): {
		"max_hp": 3,
		"drops": [{"id": "wood",  "category": "material", "min": 1, "max": 3}],
	},
	Vector2i(1, 1): {
		"max_hp": 5,
		"drops": [{"id": "stone", "category": "material", "min": 1, "max": 2}],
	},
	Vector2i(2, 2): {
		"max_hp": 2,
		"drops": [{"id": "berry", "category": "food", "min": 1, "max": 2}],
	},
}

@onready var _bus       := $"../../TileMutationBus"
@onready var _chunk_mgr := $"../../ChunkManager"

## Ephemeral tile damage state. Key: Vector2i (world tile coords).
## Value: {hp_remaining: int, last_hit_usec: int}
var _tile_damage: Dictionary = {}

## Cached world node for spawning visual effects.
var _world: Node = null

func _ready() -> void:
	# ChunkManager is a direct child of World; its parent IS World.
	if _chunk_mgr != null:
		_world = _chunk_mgr.get_parent()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	var world_px := get_viewport().get_canvas_transform().affine_inverse() \
	                * get_viewport().get_mouse_position()
	var tile_pos := Vector2i(int(floorf(world_px.x / Constants.TILE_SIZE)),
	                         int(floorf(world_px.y / Constants.TILE_SIZE)))
	_dispatch(event.button_index, tile_pos, "input")

## Test-only entry point. Synthesizes a click at the given tile_pos.
## Used by dev/Puppet.gd to drive interaction in headless scenarios without
## mocking viewport/mouse. Production clicks flow through _unhandled_input.
func puppet_click(tile_pos: Vector2i, button: int) -> void:
	_dispatch(button, tile_pos, "puppet")

## Shared click-dispatch used by both real input and the puppet harness.
## `source` is logged as "input" or "puppet" so EventLog can distinguish.
func _dispatch(button: int, tile_pos: Vector2i, source: String) -> void:
	var player := get_parent()
	var inventory: Object = player.get("inventory")

	var tool_id := ""
	if inventory != null:
		var active_tool: Dictionary = inventory.get_active_tool()
		tool_id = str(active_tool.get("id", ""))

	EventLog.record("click", {
		"tile": tile_pos, "button": button, "tool_id": tool_id, "source": source,
	})

	if tool_id == "shovel":
		_handle_shovel(button, tile_pos, player, inventory)
		return

	# Structure placement: right-click places the held structure tile.
	if STRUCTURE_TILES.has(tool_id):
		if button == MOUSE_BUTTON_RIGHT:
			_handle_structure_place(tile_pos, player, inventory, tool_id)
		return

	# Non-interactive tools: lantern is a light source, not a weapon. Click is a no-op.
	# (Toggle is on KEY_L; the tool doesn't damage tiles.)
	if tool_id == "lantern":
		return

	# Fist or melee tool (axe / pickaxe / etc.) — left click swings at tiles.
	if button == MOUSE_BUTTON_LEFT:
		_handle_melee(tile_pos, player, inventory, tool_id)

# ---------------------------------------------------------------------------
# Melee / harvest (fist, axe, pickaxe)
# ---------------------------------------------------------------------------

func _handle_melee(tile_pos: Vector2i, player: Node,
		inventory: Object, tool_id: String) -> void:
	if not _in_range(tile_pos, player):
		return
	if not player.start_swing():
		return
	_swing_tile(tile_pos, inventory, tool_id)

func _swing_tile(tile_pos: Vector2i, inventory: Object,
		tool_id: String = "") -> void:
	var tile: Dictionary = _chunk_mgr.get_object_tile_at(tile_pos)
	if tile.is_empty():
		return

	var atlas := Vector2i(int(tile.get("atlas_x", -1)), int(tile.get("atlas_y", -1)))
	if not HARVESTABLE_TILES.has(atlas):
		return

	var spec: Dictionary    = HARVESTABLE_TILES[atlas]
	var max_hp: int         = int(spec["max_hp"])
	var damage: int         = _tool_damage(atlas, tool_id)

	# Reset HP if tile hasn't been hit recently.
	var now_usec: int = Time.get_ticks_usec()
	if _tile_damage.has(tile_pos):
		var prior: Dictionary = _tile_damage[tile_pos]
		var elapsed_s: float  = (now_usec - int(prior["last_hit_usec"])) / 1_000_000.0
		if elapsed_s > DAMAGE_RESET_S:
			_tile_damage.erase(tile_pos)

	if not _tile_damage.has(tile_pos):
		_tile_damage[tile_pos] = {"hp_remaining": max_hp, "last_hit_usec": now_usec}

	var entry: Dictionary = _tile_damage[tile_pos]
	entry["hp_remaining"] -= damage
	entry["last_hit_usec"] = now_usec

	var hp_left: int = int(entry["hp_remaining"])
	print("[HARVEST] hit %s  hp=%d/%d  tool=%s" % [atlas, hp_left, max_hp, tool_id])

	# --- Visual feedback ---
	var hp_fraction: float = float(max(hp_left, 0)) / float(max_hp)
	_spawn_hit_flash(tile_pos, hp_left)
	_play_hit_sound(_atlas_type_name(atlas), hp_fraction)

	if hp_left <= 0:
		_tile_damage.erase(tile_pos)
		_bus.request_remove_tile(tile_pos, 1)
		_spawn_death_particles(tile_pos, atlas)
		_give_drops(spec, inventory)

## Returns damage per swing for the given tool against the given tile atlas.
func _tool_damage(atlas: Vector2i, tool_id: String) -> int:
	match tool_id:
		"wooden_axe":
			return 2 if atlas == Vector2i(0, 1) else 1
		"wooden_pickaxe":
			return 2 if atlas == Vector2i(1, 1) else 1
		"stone_axe":
			return 3 if atlas == Vector2i(0, 1) else 1
		"stone_pickaxe":
			return 3 if atlas == Vector2i(1, 1) else 1
		_:
			return 1  # fist or unrecognised tool

# ---------------------------------------------------------------------------
# Structure placement
# ---------------------------------------------------------------------------

## Place a structure item (campfire/workbench) on the object layer at tile_pos.
## Requires the tile to be empty on layer 1 and within DIG_RANGE_TILES.
func _handle_structure_place(tile_pos: Vector2i, player: Node,
		inventory: Object, tool_id: String) -> void:
	if not _in_range(tile_pos, player):
		return
	# Do not place on an occupied object-layer tile.
	if _chunk_mgr.has_tile_at(tile_pos, 1):
		return
	var tile_id: String = STRUCTURE_TILES[tool_id]
	_bus.request_place_tile(tile_pos, 1, tile_id)
	# Remove the structure item from the active tool slot.
	var active_idx: int = int(inventory.get("active_tool_index"))
	inventory.clear_tool_slot(active_idx)
	print("[PLACE] placed %s at %s" % [tile_id, tile_pos])

func _give_drops(spec: Dictionary, inventory: Object) -> void:
	if inventory == null:
		return
	for drop in spec.get("drops", []) as Array:
		var count: int = randi_range(int(drop["min"]), int(drop["max"]))
		inventory.add_to_bag(
			{"id": str(drop["id"]), "category": str(drop["category"]), "count": count},
			32)
		print("[HARVEST] +%d %s" % [count, drop["id"]])

# ---------------------------------------------------------------------------
# Visual feedback
# ---------------------------------------------------------------------------

func _spawn_hit_flash(tile_pos: Vector2i, hp_left: int) -> void:
	if _world == null:
		return
	var flash := TileHitFlashScript.new()
	var world_pos := Vector2(tile_pos.x * Constants.TILE_SIZE,
	                         tile_pos.y * Constants.TILE_SIZE)
	flash.position = world_pos
	if hp_left <= 0:
		# Tile is dying — bright red flash, already handled by death particles.
		# Skip flash on kill so it doesn't fight with the particle burst.
		return
	elif hp_left == 1:
		# Last hit warning: red, lingers.
		flash.setup(Color(1.0, 0.15, 0.15, 0.55), 0.8)
	else:
		# Normal hit: white, short.
		flash.setup(Color(1.0, 1.0, 1.0, 0.45), 0.13)
	_world.add_child(flash)

func _spawn_death_particles(tile_pos: Vector2i, atlas: Vector2i) -> void:
	if _world == null:
		return
	var center := Vector2(
		tile_pos.x * Constants.TILE_SIZE + Constants.TILE_SIZE * 0.5,
		tile_pos.y * Constants.TILE_SIZE + Constants.TILE_SIZE * 0.5)

	var p := CPUParticles2D.new()
	p.position = center
	p.z_index  = 3

	p.amount        = 6
	p.lifetime      = 0.45
	p.one_shot      = true
	p.explosiveness = 0.95

	p.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(Constants.TILE_SIZE * 0.35, Constants.TILE_SIZE * 0.35)

	p.direction             = Vector2(0.0, -1.0)
	p.spread                = 80.0
	p.gravity               = Vector2(0.0, 120.0)
	p.initial_velocity_min  = 25.0
	p.initial_velocity_max  = 65.0
	p.scale_amount_min      = 1.5
	p.scale_amount_max      = 3.0

	match atlas:
		Vector2i(0, 1): p.color = Color(0.25, 0.55, 0.15)  # tree → leafy green
		Vector2i(1, 1): p.color = Color(0.50, 0.48, 0.44)  # rock → stone gray
		Vector2i(2, 2): p.color = Color(0.20, 0.75, 0.20)  # plant → bright green
		_:              p.color = Color(0.65, 0.60, 0.50)

	_world.add_child(p)
	p.finished.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())

# ---------------------------------------------------------------------------
# Audio stub — wire up when assets are ready
# ---------------------------------------------------------------------------

## Called on every swing that connects with a harvestable tile.
## tile_type: "tree" | "rock"
## hp_fraction: remaining HP as 0.0–1.0 AFTER the hit (0.0 = tile just died)
##
## TODO: add an AudioStreamPlayer2D child, load .ogg files per tile type,
## and play hit_light / hit_heavy / break variants based on hp_fraction.
func _play_hit_sound(_tile_type: String, _hp_fraction: float) -> void:
	pass

func _atlas_type_name(atlas: Vector2i) -> String:
	match atlas:
		Vector2i(0, 1): return "tree"
		Vector2i(1, 1): return "rock"
		Vector2i(2, 2): return "plant"
		_:              return "unknown"

# ---------------------------------------------------------------------------
# Shovel
# ---------------------------------------------------------------------------

func _handle_shovel(button: int, tile_pos: Vector2i,
		player: Node, inventory: Object) -> void:
	if not _in_range(tile_pos, player):
		return
	if button == MOUSE_BUTTON_LEFT:
		_shovel_dig(tile_pos, inventory)
	elif button == MOUSE_BUTTON_RIGHT:
		_shovel_place(tile_pos, inventory)

func _shovel_dig(tile_pos: Vector2i, inventory: Object) -> void:
	if not _chunk_mgr.has_tile_at(tile_pos, 0):
		return
	_bus.request_remove_tile(tile_pos, 0)
	inventory.add_to_bag({"id": "dirt", "category": "material", "count": 1}, 32)

func _shovel_place(tile_pos: Vector2i, inventory: Object) -> void:
	if inventory.bag_stack_total("dirt") < 1:
		return
	if _chunk_mgr.has_tile_at(tile_pos, 0):
		return
	_bus.request_place_tile(tile_pos, 0, "dirt")
	inventory.remove_from_bag("dirt", 1)

# ---------------------------------------------------------------------------
# Range check
# ---------------------------------------------------------------------------

func _in_range(tile_pos: Vector2i, player: Node) -> bool:
	var pos: Vector2 = (player as Node2D).position
	var player_tile := Vector2i(
		int(floorf(pos.x / Constants.TILE_SIZE)),
		int(floorf(pos.y / Constants.TILE_SIZE)))
	var dx: int = abs(tile_pos.x - player_tile.x)
	var dy: int = abs(tile_pos.y - player_tile.y)
	return dx <= DIG_RANGE_TILES and dy <= DIG_RANGE_TILES
