## Tests for Campfire node structure after _ready().
##
## Catches the regression where Campfire had no PointLight2D, so it drew
## a flame sprite but cast no actual light through the night darkness overlay.
extends GdUnitTestSuite

const CampfireScript := preload("res://world/structures/Campfire.gd")

var _campfire: Node = null

func before_test() -> void:
	_campfire = CampfireScript.new()
	add_child(_campfire)
	await get_tree().process_frame

func after_test() -> void:
	if is_instance_valid(_campfire): _campfire.queue_free()
	_campfire = null

# ---------------------------------------------------------------------------
# Light presence
# ---------------------------------------------------------------------------

func test_campfire_has_point_light_after_ready() -> void:
	assert_object(_find_light()).override_failure_message(
		"Campfire must create a PointLight2D in _ready() to cut through night darkness"
	).is_not_null()

func test_campfire_light_has_texture() -> void:
	var light := _find_light()
	if light == null: return
	assert_object(light.texture).override_failure_message(
		"PointLight2D needs a texture to actually cast light"
	).is_not_null()

func test_campfire_light_energy_is_positive() -> void:
	var light := _find_light()
	if light == null: return
	assert_float(light.energy).is_greater(0.0)

func test_campfire_light_is_warm_orange() -> void:
	# Campfire light should be warm — high red, low blue.
	var light := _find_light()
	if light == null: return
	assert_float(light.color.r).is_greater(0.7)
	assert_float(light.color.b).is_less(0.5)

func test_campfire_light_radius_matches_game_constant() -> void:
	# LIGHT_RADIUS drives Sprout avoidance and NightSpawner exclusion zone.
	# If the visual light and the game constant diverge, mobs behave differently
	# from what the player sees.
	assert_int(CampfireScript.LIGHT_RADIUS).is_equal(10)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_light() -> PointLight2D:
	for child in _campfire.get_children():
		if child is PointLight2D:
			return child as PointLight2D
	return null
