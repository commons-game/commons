## Smoke tests: verify MainMenu and GameConfig scripts parse without errors.
extends GdUnitTestSuite

const MainMenuScript := preload("res://ui/MainMenu.gd")
const GameConfigScript := preload("res://autoloads/GameConfig.gd")

func test_main_menu_compiles() -> void:
	assert_object(MainMenuScript).is_not_null()

func test_game_config_compiles() -> void:
	assert_object(GameConfigScript).is_not_null()
