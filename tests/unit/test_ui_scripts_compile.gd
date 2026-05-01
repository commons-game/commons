## Smoke tests: verify all UI scripts parse without errors.
## If any script has a GDScript parse error, preload() returns null
## and the corresponding test fails immediately.
extends GdUnitTestSuite

const ChatInputScript        := preload("res://ui/ChatInput.gd")
const ChatHistoryPanelScript := preload("res://ui/ChatHistoryPanel.gd")
const ShiftingLandsHUDScript := preload("res://ui/ShiftingLandsHUD.gd")
const SpeechBubbleScript     := preload("res://ui/SpeechBubble.gd")
const ActionBarHUDScript     := preload("res://ui/ActionBarHUD.gd")
const MainMenuScript         := preload("res://ui/MainMenu.gd")

func test_chat_input_compiles() -> void:
	assert_object(ChatInputScript).is_not_null()

func test_chat_history_panel_compiles() -> void:
	assert_object(ChatHistoryPanelScript).is_not_null()

func test_speech_bubble_compiles() -> void:
	assert_object(SpeechBubbleScript).is_not_null()

func test_action_bar_hud_compiles() -> void:
	assert_object(ActionBarHUDScript).is_not_null()

func test_main_menu_compiles() -> void:
	assert_object(MainMenuScript).is_not_null()

func test_shifting_lands_hud_compiles() -> void:
	assert_object(ShiftingLandsHUDScript).is_not_null()
