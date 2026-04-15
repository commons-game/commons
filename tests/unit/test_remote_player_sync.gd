## Structural regression tests for RemotePlayer multiplayer sync.
##
## Catches the class of bug where an agent adds new synced vars but accidentally
## drops existing ones — the equipment system retrospective found RemotePlayer had
## its original 5 appearance vars stripped when 3 equipment vars were added.
##
## Tests intentionally enumerate every expected synced var by name so any removal
## or rename fails loudly here before it reaches a live multiplayer session.
extends GdUnitTestSuite

const EXPECTED_SYNCED_VARS: Array[String] = [
	"appearance_base_body_id",
	"appearance_held_item_id",
	"appearance_facing_x",
	"appearance_facing_y",
	"appearance_walk_frame",
	"appearance_armor_id",
	"appearance_head_id",
	"appearance_feet_id",
	"player_display_name",
]

# ---------------------------------------------------------------------------
# Property existence — no scene tree needed
# ---------------------------------------------------------------------------

func test_all_synced_vars_exist_on_script() -> void:
	# Instantiate without adding to tree — just checks var declarations.
	var rp = load("res://player/RemotePlayer.tscn").instantiate()
	for var_name in EXPECTED_SYNCED_VARS:
		assert_bool(var_name in rp).is_true()
	rp.free()

func test_default_values_are_neutral() -> void:
	var rp = load("res://player/RemotePlayer.tscn").instantiate()
	assert_str(rp.appearance_base_body_id).is_equal("default")
	assert_str(rp.appearance_held_item_id).is_equal("")
	assert_float(rp.appearance_facing_x).is_equal(0.0)
	assert_float(rp.appearance_facing_y).is_equal(-1.0)
	assert_int(rp.appearance_walk_frame).is_equal(0)
	assert_str(rp.appearance_armor_id).is_equal("")
	assert_str(rp.appearance_head_id).is_equal("")
	assert_str(rp.appearance_feet_id).is_equal("")
	assert_str(rp.player_display_name).is_equal("")
	rp.free()

# ---------------------------------------------------------------------------
# Replication config — requires scene tree so _enter_tree fires
# ---------------------------------------------------------------------------

func test_replication_config_has_correct_property_count() -> void:
	# Position (1) + 8 appearance vars + player_display_name (1) = 10 total replicated properties.
	var rp = load("res://player/RemotePlayer.tscn").instantiate()
	rp.name = "RemotePlayer_1"
	add_child(rp)
	await get_tree().process_frame

	var sync: MultiplayerSynchronizer = rp.get_node("MultiplayerSynchronizer")
	var config: SceneReplicationConfig = sync.replication_config
	assert_int(config.get_properties().size()).is_equal(10)

	rp.queue_free()

func test_replication_config_includes_position() -> void:
	var rp = load("res://player/RemotePlayer.tscn").instantiate()
	rp.name = "RemotePlayer_1"
	add_child(rp)
	await get_tree().process_frame

	var sync: MultiplayerSynchronizer = rp.get_node("MultiplayerSynchronizer")
	var props: Array = sync.replication_config.get_properties()
	var prop_strings: Array = props.map(func(p): return str(p))
	assert_bool(prop_strings.has(".:position")).is_true()

	rp.queue_free()

func test_replication_config_includes_all_appearance_vars() -> void:
	var rp = load("res://player/RemotePlayer.tscn").instantiate()
	rp.name = "RemotePlayer_1"
	add_child(rp)
	await get_tree().process_frame

	var sync: MultiplayerSynchronizer = rp.get_node("MultiplayerSynchronizer")
	var props: Array = sync.replication_config.get_properties()
	var prop_strings: Array = props.map(func(p): return str(p))
	for var_name in EXPECTED_SYNCED_VARS:
		assert_bool(prop_strings.has(".:"+var_name)).is_true()

	rp.queue_free()
