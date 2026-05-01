## Tests for IslandRegistry — the autoload tracking all islands in a session.
##
## Phase 0b: registry creates one default implicit island at startup; for now
## island_for() always returns it (Phase 0c will resolve via the player's
## actual island membership, Phase 0d will create/merge/destroy islands in
## response to MergeCoordinator events).
##
## These tests construct the registry directly via `.new()` rather than
## relying on the autoload singleton, so they can pin behaviour without
## depending on global state. (The autoload entry is verified by the fact
## that the project still compiles and runs.)
extends GdUnitTestSuite

const IslandRegistryScript := preload("res://autoloads/IslandRegistry.gd")
const IslandScript := preload("res://world/Island.gd")

func _make_registry():
	# IslandRegistry extends Node. _ready() seeds the default island, but
	# _ready() doesn't fire until the node enters the scene tree, so add it
	# under the test suite (auto_free disposes it at the end of the test).
	var r = auto_free(IslandRegistryScript.new())
	add_child(r)
	return r

# --- Default island bootstrap ---

func test_default_island_exists_after_init() -> void:
	var r = _make_registry()
	var island = r.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	assert_object(island).is_not_null()
	assert_str(island.id).is_equal(IslandRegistryScript.DEFAULT_ISLAND_ID)

func test_default_island_owns_a_clock() -> void:
	var r = _make_registry()
	var island = r.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	assert_object(island.clock).is_not_null()
	assert_bool(island.clock.has_method("is_daytime")).is_true()

func test_all_islands_includes_default_after_init() -> void:
	var r = _make_registry()
	var islands = r.all_islands()
	assert_int(islands.size()).is_equal(1)

# --- island_for() — Phase 0b: ignore arg, always return default ---

func test_island_for_returns_default_for_any_arg() -> void:
	var r = _make_registry()
	var default_island = r.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	# The arg is intentionally untyped/ignored in Phase 0b; verify across a
	# few representative shapes.
	assert_object(r.island_for("any-session-id")).is_same(default_island)
	assert_object(r.island_for(null)).is_same(default_island)
	assert_object(r.island_for(42)).is_same(default_island)

# --- register_island / unregister_island ---

func test_register_island_adds_to_registry() -> void:
	var r = _make_registry()
	var extra = IslandScript.new("extra")
	r.register_island(extra)
	assert_object(r.get_island("extra")).is_same(extra)
	assert_int(r.all_islands().size()).is_equal(2)

func test_unregister_island_removes_non_default() -> void:
	var r = _make_registry()
	var extra = IslandScript.new("extra")
	r.register_island(extra)
	r.unregister_island("extra")
	assert_object(r.get_island("extra")).is_null()
	assert_int(r.all_islands().size()).is_equal(1)

func test_unregister_default_island_is_a_noop() -> void:
	# The default island must persist for the whole session; removing it
	# would leave island_for() returning null and break every caller.
	var r = _make_registry()
	r.unregister_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	var island = r.get_island(IslandRegistryScript.DEFAULT_ISLAND_ID)
	assert_object(island).is_not_null()
	assert_int(r.all_islands().size()).is_equal(1)

# --- get_island ---

func test_get_island_returns_null_for_unknown_id() -> void:
	var r = _make_registry()
	assert_object(r.get_island("nonexistent")).is_null()
