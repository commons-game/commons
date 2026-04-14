## Tests for PlayerIdentity — persistent UUID generation and storage.
extends GdUnitTestSuite

const TEMP_PATH := "user://test_player_identity_tmp.cfg"

func after_test() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))

func _is_uuid_v4(s: String) -> bool:
	## UUID v4: 8-4-4-4-12 hex groups, version nibble = 4, variant bits = 8/9/a/b
	if s.length() != 36:
		return false
	if s[8] != "-" or s[13] != "-" or s[18] != "-" or s[23] != "-":
		return false
	if s[14] != "4":  # version 4
		return false
	if not s[19] in ["8", "9", "a", "b"]:  # variant
		return false
	var hex_chars := "0123456789abcdef"
	for i in s.length():
		if i in [8, 13, 18, 23]:
			continue
		if not hex_chars.contains(s[i]):
			return false
	return true

func test_generated_uuid_is_valid_v4() -> void:
	var id := PlayerIdentity._generate_uuid()
	assert_bool(_is_uuid_v4(id)).is_true()

func test_two_generated_uuids_are_different() -> void:
	var a := PlayerIdentity._generate_uuid()
	var b := PlayerIdentity._generate_uuid()
	assert_str(a).is_not_equal(b)

func test_load_or_generate_creates_file_when_missing() -> void:
	assert_bool(FileAccess.file_exists(TEMP_PATH)).is_false()
	var id := PlayerIdentity._load_or_generate(TEMP_PATH)
	assert_bool(FileAccess.file_exists(TEMP_PATH)).is_true()
	assert_bool(_is_uuid_v4(id)).is_true()

func test_load_or_generate_returns_same_id_on_second_call() -> void:
	var first  := PlayerIdentity._load_or_generate(TEMP_PATH)
	var second := PlayerIdentity._load_or_generate(TEMP_PATH)
	assert_str(first).is_equal(second)

func test_identity_id_is_non_empty_string() -> void:
	assert_str(PlayerIdentity.id).is_not_empty()
