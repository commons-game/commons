## Tests for MobSpawner.
extends GdUnitTestSuite

const MobSpawnerScript := preload("res://world/mobs/MobSpawner.gd")

var _cm: ChunkManager
var _spawner: Node
var _parent: Node

func before_test() -> void:
	_cm = ChunkManager.new()
	add_child(_cm)
	_cm.update_player_position(Vector2i(0, 0))
	await get_tree().process_frame

	_spawner = MobSpawnerScript.new()
	add_child(_spawner)

	_parent = Node2D.new()
	add_child(_parent)

func after_test() -> void:
	if is_instance_valid(_parent):
		_parent.queue_free()
	if is_instance_valid(_spawner):
		_spawner.queue_free()
	if is_instance_valid(_cm):
		_cm.queue_free()
	_cm = null
	_spawner = null
	_parent = null

func test_spawn_returns_mob_nodes() -> void:
	# Spawn 2 mobs near origin; retry loop must place exactly the requested count.
	var mobs: Array = _spawner.spawn(Vector2i(0, 0), 2, 4, _cm, null, _parent)
	assert_int(mobs.size()).is_equal(2)
	for mob in mobs:
		assert_bool("mob_died" in mob).is_true()

func test_spawn_skips_water() -> void:
	# Fill the origin chunk with water on ground layer so no mob lands on land.
	for lx in range(-8, 9):
		for ly in range(-8, 9):
			_cm.place_tile(Vector2i(lx, ly), 0, 0, Vector2i(3, 0), 0, "test")
	var mobs: Array = _spawner.spawn(Vector2i(0, 0), 5, 4, _cm, null, _parent)
	assert_int(mobs.size()).is_equal(0)
