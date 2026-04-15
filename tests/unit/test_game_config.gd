## Tests for GameConfig autoload — verifies defaults and mutation.
extends GdUnitTestSuite

func test_default_mode_is_empty() -> void:
	# GameConfig is an autoload — reset to known state before testing.
	GameConfig.mode = ""
	assert_str(GameConfig.mode).is_equal("")

func test_setting_mode_host_persists() -> void:
	GameConfig.mode = "host"
	assert_str(GameConfig.mode).is_equal("host")
	GameConfig.mode = ""  # restore

func test_setting_host_ip_persists() -> void:
	var original := GameConfig.host_ip
	GameConfig.host_ip = "10.0.0.99"
	assert_str(GameConfig.host_ip).is_equal("10.0.0.99")
	GameConfig.host_ip = original  # restore

func test_default_port_is_7777() -> void:
	assert_int(GameConfig.port).is_equal(7777)
