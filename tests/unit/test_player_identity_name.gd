## Tests for PlayerIdentity.save_display_name() — name persistence.
extends GdUnitTestSuite

var _original_name: String = ""

func before_test() -> void:
	_original_name = PlayerIdentity.display_name

func after_test() -> void:
	# Restore original name so other tests are unaffected.
	PlayerIdentity.display_name = _original_name

func test_save_display_name_sets_property() -> void:
	PlayerIdentity.save_display_name("Alice")
	assert_str(PlayerIdentity.display_name).is_equal("Alice")

func test_save_display_name_returns_saved_value() -> void:
	PlayerIdentity.save_display_name("Bob")
	assert_str(PlayerIdentity.display_name).is_equal("Bob")

func test_empty_string_is_rejected() -> void:
	PlayerIdentity.save_display_name("Charlie")
	PlayerIdentity.save_display_name("")
	assert_str(PlayerIdentity.display_name).is_equal("Charlie")

func test_whitespace_only_is_rejected() -> void:
	PlayerIdentity.save_display_name("Dana")
	PlayerIdentity.save_display_name("   ")
	assert_str(PlayerIdentity.display_name).is_equal("Dana")

func test_name_longer_than_20_chars_is_truncated() -> void:
	PlayerIdentity.save_display_name("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
	assert_str(PlayerIdentity.display_name).is_equal("ABCDEFGHIJKLMNOPQRST")
	assert_int(PlayerIdentity.display_name.length()).is_equal(20)
