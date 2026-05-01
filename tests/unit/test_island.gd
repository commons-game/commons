## Tests for Island — a single "reality bubble" owning its own DayClockInstance.
##
## Phase 0b of the per-island clock refactor: Island wraps an id, a member
## list (session_ids), and one DayClockInstance. No production code uses
## Island yet (Phase 0c will plumb DayClock through the player's island);
## these tests pin the API shape so 0c/0d can build on it confidently.
extends GdUnitTestSuite

const IslandScript := preload("res://world/Island.gd")
const DayClockInstanceScript := preload("res://world/DayClockInstance.gd")

# --- Construction / identity ---

func test_island_has_id_from_constructor() -> void:
	var island = IslandScript.new("a")
	assert_str(island.id).is_equal("a")

func test_island_owns_a_day_clock_instance() -> void:
	var island = IslandScript.new("a")
	assert_object(island.clock).is_not_null()
	# The clock must be a DayClockInstance — i.e. it must answer the
	# DayClockInstance API (is_daytime, phase_fraction, tick).
	assert_bool(island.clock.has_method("is_daytime")).is_true()
	assert_bool(island.clock.has_method("phase_fraction")).is_true()
	assert_bool(island.clock.has_method("tick")).is_true()

func test_island_starts_with_no_members() -> void:
	var island = IslandScript.new("a")
	assert_int(island.members.size()).is_equal(0)

# --- Membership ---

func test_add_member_appends() -> void:
	var island = IslandScript.new("a")
	island.add_member("session-1")
	assert_int(island.members.size()).is_equal(1)
	assert_bool(island.has_member("session-1")).is_true()

func test_add_member_is_idempotent() -> void:
	var island = IslandScript.new("a")
	island.add_member("session-1")
	island.add_member("session-1")
	assert_int(island.members.size()).is_equal(1)

func test_remove_member_removes() -> void:
	var island = IslandScript.new("a")
	island.add_member("session-1")
	island.add_member("session-2")
	island.remove_member("session-1")
	assert_bool(island.has_member("session-1")).is_false()
	assert_bool(island.has_member("session-2")).is_true()
	assert_int(island.members.size()).is_equal(1)

func test_remove_unknown_member_is_a_noop() -> void:
	var island = IslandScript.new("a")
	island.add_member("session-1")
	island.remove_member("never-joined")
	assert_int(island.members.size()).is_equal(1)
	assert_bool(island.has_member("session-1")).is_true()

func test_has_member_false_when_absent() -> void:
	var island = IslandScript.new("a")
	assert_bool(island.has_member("session-1")).is_false()

# --- Independence between islands (the whole point of the refactor) ---

func test_two_islands_have_independent_clocks() -> void:
	var a = IslandScript.new("a")
	var b = IslandScript.new("b")
	# Pin both clocks to known anchors so independence is observable
	# without depending on wall-clock timing.
	a.clock._time_override = 0.0       # phase 0 (dawn) — daytime
	b.clock._time_override = 5400.0    # phase 0.75 (midnight) — nighttime
	assert_bool(a.clock.is_daytime()).is_true()
	assert_bool(b.clock.is_daytime()).is_false()
	# Advancing one must not move the other.
	a.clock.advance_to_phase(0.5)
	assert_bool(a.clock.is_daytime()).is_false()
	assert_float(b.clock.phase_fraction()).is_equal_approx(0.75, 0.001)

func test_two_islands_have_independent_members() -> void:
	var a = IslandScript.new("a")
	var b = IslandScript.new("b")
	a.add_member("session-1")
	b.add_member("session-2")
	assert_bool(a.has_member("session-1")).is_true()
	assert_bool(a.has_member("session-2")).is_false()
	assert_bool(b.has_member("session-2")).is_true()
	assert_bool(b.has_member("session-1")).is_false()
