## Tests for ModBundle — parsing mod definitions from JSON.
## TDD: these tests define the expected API before implementation.
extends GdUnitTestSuite

const ModBundleScript := preload("res://mods/ModBundle.gd")

# Minimal valid bundle JSON with all required top-level keys.
func _minimal_json(overrides: Dictionary = {}) -> String:
	var base := {"tiles": [], "entities": [], "items": [], "buffs": []}
	base.merge(overrides, true)
	return JSON.stringify(base)

# --- Empty bundle ---

func test_empty_bundle_has_zero_defs() -> void:
	var bundle = ModBundleScript.new()
	bundle.load_from_json(_minimal_json())
	assert_that(bundle.tile_defs.size()).is_equal(0)
	assert_that(bundle.entity_defs.size()).is_equal(0)
	assert_that(bundle.item_defs.size()).is_equal(0)
	assert_that(bundle.buff_defs.size()).is_equal(0)

# --- TileDef parsing ---

func test_tile_def_basic_fields() -> void:
	var bundle = ModBundleScript.new()
	bundle.load_from_json(_minimal_json({"tiles": [{
		"id": "sticky_trap",
		"solid": false,
		"tags": ["trap", "ground"],
		"decay_rate": 1.5
	}]}))
	assert_that(bundle.tile_defs.has("sticky_trap")).is_true()
	var td = bundle.tile_defs["sticky_trap"]
	assert_that(td.id).is_equal("sticky_trap")
	assert_that(td.solid).is_false()
	assert_that(td.tags.has("trap")).is_true()
	assert_that(td.tags.has("ground")).is_true()
	assert_that(td.decay_rate).is_equal_approx(1.5, 0.001)

func test_tile_def_defaults_when_fields_missing() -> void:
	# Only 'id' is required; all other fields have safe defaults.
	var bundle = ModBundleScript.new()
	bundle.load_from_json(_minimal_json({"tiles": [{"id": "bare_tile"}]}))
	var td = bundle.tile_defs["bare_tile"]
	assert_that(td.solid).is_false()
	assert_that(td.tags.size()).is_equal(0)
	assert_that(td.decay_rate).is_equal_approx(1.0, 0.001)
	assert_that(td.on_walk.size()).is_equal(0)
	assert_that(td.on_place.size()).is_equal(0)
	assert_that(td.on_remove.size()).is_equal(0)

func test_multiple_tile_defs_keyed_by_id() -> void:
	var bundle = ModBundleScript.new()
	bundle.load_from_json(_minimal_json({"tiles": [
		{"id": "grass"},
		{"id": "stone"},
		{"id": "lava"}
	]}))
	assert_that(bundle.tile_defs.size()).is_equal(3)
	assert_that(bundle.tile_defs.has("grass")).is_true()
	assert_that(bundle.tile_defs.has("stone")).is_true()
	assert_that(bundle.tile_defs.has("lava")).is_true()

# --- EventHandler / trigger parsing ---

func test_tile_on_walk_parses_effect() -> void:
	var bundle = ModBundleScript.new()
	bundle.load_from_json(_minimal_json({"tiles": [{
		"id": "trap",
		"on_walk": [{
			"effects": [{"type": "deal_damage", "amount": 10, "damage_type": "fire"}]
		}]
	}]}))
	var td = bundle.tile_defs["trap"]
	assert_that(td.on_walk.size()).is_equal(1)
	var handler = td.on_walk[0]
	assert_that(handler.condition).is_null()
	assert_that(handler.effects.size()).is_equal(1)
	assert_that(handler.effects[0].type).is_equal("deal_damage")
	assert_that(int(handler.effects[0].params["amount"])).is_equal(10)

func test_tile_on_walk_parses_condition() -> void:
	var bundle = ModBundleScript.new()
	bundle.load_from_json(_minimal_json({"tiles": [{
		"id": "ghost_floor",
		"on_walk": [{
			"condition": {"type": "has_tag", "tag": "ghost"},
			"effects": [{"type": "apply_buff", "buff_ref": "phase", "duration": 5.0}]
		}]
	}]}))
	var handler = bundle.tile_defs["ghost_floor"].on_walk[0]
	assert_that(handler.condition).is_not_null()
	assert_that(handler.condition.type).is_equal("has_tag")
	assert_that(handler.condition.params["tag"]).is_equal("ghost")

# --- BuffDef parsing ---

func test_buff_def_basic_fields() -> void:
	var bundle = ModBundleScript.new()
	bundle.load_from_json(_minimal_json({"buffs": [{
		"id": "slowed",
		"speed_modifier": 0.5,
		"duration": 5.0
	}]}))
	assert_that(bundle.buff_defs.has("slowed")).is_true()
	var bd = bundle.buff_defs["slowed"]
	assert_that(bd.id).is_equal("slowed")
	assert_that(bd.speed_modifier).is_equal_approx(0.5, 0.001)
	assert_that(bd.duration).is_equal_approx(5.0, 0.001)

# --- Invalid / malformed input ---

func test_missing_id_tile_is_skipped() -> void:
	# A tile without 'id' cannot be keyed — must be silently skipped.
	var bundle = ModBundleScript.new()
	bundle.load_from_json(_minimal_json({"tiles": [{"solid": true}]}))
	assert_that(bundle.tile_defs.size()).is_equal(0)

func test_invalid_json_returns_empty_bundle() -> void:
	var bundle = ModBundleScript.new()
	bundle.load_from_json("this is not json {{{")
	assert_that(bundle.tile_defs.size()).is_equal(0)
