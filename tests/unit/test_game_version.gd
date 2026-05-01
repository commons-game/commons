## Tests for GameVersion autoload — the constants are well-formed AND the
## boot-time version print is present.
##
## Regression target: a recent playtest ran an Apr-23 binary even though the
## fix landed on Apr 30, because dev/play.sh rsync'd build/ blindly without
## ever invoking dev/build.sh. The fix stamps the git SHA into
## GameVersion.GAME_VERSION at export time and prints it at boot, so the next
## "is this the right binary?" question is answerable from godot.log alone.
##
## We don't actually invoke dev/build.sh from the test (Godot export is slow
## and CI-fragile). We just assert the constant has a parseable shape and that
## a _ready() exists to print it at boot. A botched stamp (empty string,
## garbled sed output) trips the regex test; removing the boot print trips
## the _ready test.
extends GdUnitTestSuite

const GameVersionScript := preload("res://autoloads/GameVersion.gd")

func test_game_version_is_non_empty_string() -> void:
	assert_str(GameVersion.GAME_VERSION).is_not_empty()

func test_protocol_version_is_positive_int() -> void:
	# Sanity: a zero or negative protocol version would silently break the
	# MergeCoordinator pairing gate (which compares against 0 as "unknown").
	assert_int(GameVersion.PROTOCOL_VERSION).is_greater(0)

func test_game_version_matches_dev_or_git_sha_pattern() -> void:
	# Either the literal "dev" (uncommitted local builds, editor runs) or a
	# git SHA optionally followed by space + ISO timestamp (stamped by
	# dev/build.sh). Anything else (empty, garbled sed, accidental newline)
	# means the export-time stamp got corrupted.
	var v: String = GameVersion.GAME_VERSION
	var re := RegEx.new()
	var ok := re.compile("^(dev|[0-9a-f]{7,40}( .*)?)$")
	assert_int(ok).override_failure_message("regex failed to compile").is_equal(OK)
	var m := re.search(v)
	assert_object(m).override_failure_message(
		"GameVersion.GAME_VERSION = %s — expected 'dev' or '<git-sha> [iso-date]'. " % [v]
		+ "If this fails after dev/build.sh ran, the sed-replace probably mangled the file."
	).is_not_null()

func test_game_version_script_defines_ready_with_boot_print() -> void:
	# The whole point of the workflow fix: a boot-time line in godot.log
	# tells us which binary is running. If _ready() (and its print) goes
	# missing the next "is this build current?" question becomes
	# unanswerable again.
	#
	# `has_method("_ready")` returns true for every Node, so we can't use
	# that to detect the override. Instead, walk the script's own method
	# list — only methods defined in this script appear there.
	# get_script_method_list is non-static, must be called on an instance.
	var inst: Node = GameVersionScript.new()
	var script_methods: Array = inst.get_script().get_script_method_list()
	inst.queue_free()
	var has_ready := false
	for m in script_methods:
		if str(m.get("name", "")) == "_ready":
			has_ready = true
			break
	assert_bool(has_ready).override_failure_message(
		"GameVersion.gd does not define _ready() — boot log will be missing the version " +
		"stamp, and the next stale-binary playtest will be just as opaque as the last one."
	).is_true()

	# Belt-and-braces: the script source itself contains a print of GAME_VERSION
	# so a future contributor doesn't accidentally make _ready() silent.
	var src: String = (load("res://autoloads/GameVersion.gd") as GDScript).source_code
	assert_bool(src.contains("print") and src.contains("GAME_VERSION")).override_failure_message(
		"GameVersion.gd defines _ready() but doesn't print(GAME_VERSION) in it — " +
		"the boot log line is the whole reason _ready exists here."
	).is_true()
