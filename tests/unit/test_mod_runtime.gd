## Tests for ModRuntime — trigger evaluation and condition filtering.
## Tests drive the API before implementation exists.
extends GdUnitTestSuite

const ModBundleScript := preload("res://mods/ModBundle.gd")
const ModRuntimeScript := preload("res://mods/ModRuntime.gd")

# Build a bundle from a JSON dict (convenience wrapper).
func _bundle(data: Dictionary) -> Object:
	var b = ModBundleScript.new()
	b.load_from_json(JSON.stringify(
		{"tiles": data.get("tiles", []), "entities": [],
		 "items": [], "buffs": data.get("buffs", [])}
	))
	return b

# Build a trigger context dictionary (what the runtime receives).
func _ctx(trigger: String, entity_tags: Array = [], extra: Dictionary = {}) -> Dictionary:
	var c := {"trigger": trigger, "entity_tags": entity_tags}
	c.merge(extra, true)
	return c

# --- No handlers ---

func test_no_handlers_returns_empty_effects() -> void:
	var bundle = _bundle({"tiles": [{"id": "plain_tile"}]})
	var runtime = ModRuntimeScript.new()
	var effects := runtime.get_effects("plain_tile", _ctx("on_walk"), bundle)
	assert_that(effects.size()).is_equal(0)

# --- Handler fires without condition ---

func test_unconditional_handler_fires() -> void:
	var bundle = _bundle({"tiles": [{
		"id": "trap",
		"on_walk": [{"effects": [{"type": "deal_damage", "amount": 10}]}]
	}]})
	var runtime = ModRuntimeScript.new()
	var effects := runtime.get_effects("trap", _ctx("on_walk"), bundle)
	assert_that(effects.size()).is_equal(1)
	assert_that(effects[0].type).is_equal("deal_damage")

# --- Condition: has_tag ---

func test_has_tag_condition_matches() -> void:
	var bundle = _bundle({"tiles": [{
		"id": "ghost_floor",
		"on_walk": [{
			"condition": {"type": "has_tag", "tag": "ghost"},
			"effects": [{"type": "apply_buff", "buff_ref": "phase", "duration": 5.0}]
		}]
	}]})
	var runtime = ModRuntimeScript.new()
	var effects := runtime.get_effects(
		"ghost_floor", _ctx("on_walk", ["ghost"]), bundle)
	assert_that(effects.size()).is_equal(1)

func test_has_tag_condition_no_match_skips_handler() -> void:
	var bundle = _bundle({"tiles": [{
		"id": "ghost_floor",
		"on_walk": [{
			"condition": {"type": "has_tag", "tag": "ghost"},
			"effects": [{"type": "apply_buff", "buff_ref": "phase", "duration": 5.0}]
		}]
	}]})
	var runtime = ModRuntimeScript.new()
	var effects := runtime.get_effects(
		"ghost_floor", _ctx("on_walk", ["player"]), bundle)
	assert_that(effects.size()).is_equal(0)

# --- Condition: random ---

func test_random_condition_zero_never_fires() -> void:
	var bundle = _bundle({"tiles": [{
		"id": "dud_tile",
		"on_walk": [{
			"condition": {"type": "random", "probability": 0.0},
			"effects": [{"type": "deal_damage", "amount": 5}]
		}]
	}]})
	var runtime = ModRuntimeScript.new()
	for _i in range(20):
		var effects := runtime.get_effects("dud_tile", _ctx("on_walk"), bundle)
		assert_that(effects.size()).is_equal(0)

func test_random_condition_one_always_fires() -> void:
	var bundle = _bundle({"tiles": [{
		"id": "sure_tile",
		"on_walk": [{
			"condition": {"type": "random", "probability": 1.0},
			"effects": [{"type": "deal_damage", "amount": 5}]
		}]
	}]})
	var runtime = ModRuntimeScript.new()
	for _i in range(20):
		var effects := runtime.get_effects("sure_tile", _ctx("on_walk"), bundle)
		assert_that(effects.size()).is_equal(1)

# --- Multiple handlers, multiple effects ---

func test_multiple_handlers_accumulate_effects() -> void:
	var bundle = _bundle({"tiles": [{
		"id": "combo_tile",
		"on_walk": [
			{"effects": [{"type": "deal_damage", "amount": 5}]},
			{"effects": [{"type": "play_sound", "sound_ref": "zap"}]}
		]
	}]})
	var runtime = ModRuntimeScript.new()
	var effects := runtime.get_effects("combo_tile", _ctx("on_walk"), bundle)
	assert_that(effects.size()).is_equal(2)

# --- Wrong trigger type returns no effects ---

func test_on_place_does_not_fire_on_walk() -> void:
	var bundle = _bundle({"tiles": [{
		"id": "place_tile",
		"on_place": [{"effects": [{"type": "play_sound", "sound_ref": "thud"}]}]
	}]})
	var runtime = ModRuntimeScript.new()
	var effects := runtime.get_effects("place_tile", _ctx("on_walk"), bundle)
	assert_that(effects.size()).is_equal(0)

# --- Unknown tile id ---

func test_unknown_tile_id_returns_empty() -> void:
	var bundle = _bundle({})
	var runtime = ModRuntimeScript.new()
	var effects := runtime.get_effects("no_such_tile", _ctx("on_walk"), bundle)
	assert_that(effects.size()).is_equal(0)
