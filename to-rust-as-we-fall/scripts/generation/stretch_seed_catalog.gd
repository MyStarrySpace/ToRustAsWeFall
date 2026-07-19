class_name StretchSeedCatalog
extends RefCounted

const DEFAULT_PATH := "res://data/generation/stretch_seed_corpus.json"
const CONTRACT_ID := "stretch_seed_corpus_v1"
const VALID_STATUSES := ["candidate", "tuning", "blocked", "approved"]
const VALID_TIERS := ["teaching", "standard", "hard", "setpiece"]
const VALID_FOOD_TESTS := ["neutral", "return_loop", "scarcity"]
const GAME_MODE_BY_FOOD_TEST := {
	"neutral": "neutral",
	"return_loop": "expedition",
	"scarcity": "scarcity",
}
const FOOD_TEST_BY_GAME_MODE := {
	"neutral": "neutral",
	"expedition": "return_loop",
	"scarcity": "scarcity",
}
const DEFAULT_STAGE_BY_TIER := {
	"teaching": 2,
	"standard": 3,
	"hard": 4,
	"setpiece": 5,
}


static func load_catalog(path := DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {
			"contract_id": CONTRACT_ID,
			"cases": [],
			"validation": {"valid": false, "errors": ["Seed corpus not found: %s" % path]},
		}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"contract_id": CONTRACT_ID,
			"cases": [],
			"validation": {"valid": false, "errors": ["Seed corpus could not be opened: %s" % path]},
		}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {
			"contract_id": CONTRACT_ID,
			"cases": [],
			"validation": {"valid": false, "errors": ["Seed corpus is not a JSON object: %s" % path]},
		}
	var catalog := (parsed as Dictionary).duplicate(true)
	catalog["validation"] = validate_catalog(catalog)
	return catalog


static func validate_catalog(catalog: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if str(catalog.get("contract_id", "")) != CONTRACT_ID:
		errors.append("Expected contract_id %s." % CONTRACT_ID)
	var principles: Variant = catalog.get("evaluation_principles", [])
	if not (principles is Array) or (principles as Array).is_empty():
		errors.append("Seed corpus must state its cross-seed evaluation principles.")
	else:
		var seen_principles := {}
		for raw_principle in principles as Array:
			if not (raw_principle is Dictionary):
				errors.append("Every evaluation principle must be an object.")
				continue
			var principle := raw_principle as Dictionary
			var principle_id := str(principle.get("id", "")).strip_edges()
			if principle_id == "" or str(principle.get("rule", "")).strip_edges() == "":
				errors.append("Every evaluation principle needs an id and rule.")
			elif seen_principles.has(principle_id):
				errors.append("Duplicate evaluation principle id: %s." % principle_id)
			else:
				seen_principles[principle_id] = true
	_validate_play_config(catalog.get("default_play_config", {}), "default_play_config", errors)
	var raw_cases: Variant = catalog.get("cases", [])
	if not (raw_cases is Array) or (raw_cases as Array).is_empty():
		errors.append("Seed corpus must contain at least one case.")
		return {"valid": errors.is_empty(), "errors": errors}
	var seen_ids := {}
	for index in range((raw_cases as Array).size()):
		var raw_case: Variant = (raw_cases as Array)[index]
		if not (raw_case is Dictionary):
			errors.append("Case %d is not an object." % index)
			continue
		var case_def := raw_case as Dictionary
		var case_id := str(case_def.get("id", "")).strip_edges()
		if case_id == "":
			errors.append("Case %d has no id." % index)
		elif seen_ids.has(case_id):
			errors.append("Duplicate seed case id: %s." % case_id)
		else:
			seen_ids[case_id] = true
		var status := str(case_def.get("status", ""))
		if not VALID_STATUSES.has(status):
			errors.append("Case %s has invalid status '%s'." % [case_id, status])
		var settings: Variant = case_def.get("settings", {})
		if not (settings is Dictionary) or (settings as Dictionary).is_empty():
			errors.append("Case %s has no generator settings." % case_id)
			continue
		var tier := str((settings as Dictionary).get("complexity_tier", ""))
		if not VALID_TIERS.has(tier):
			errors.append("Case %s has invalid complexity tier '%s'." % [case_id, tier])
		if int(case_def.get("seed", 0)) != int((settings as Dictionary).get("seed", 0)):
			errors.append("Case %s seed does not match settings.seed." % case_id)
		if str(case_def.get("purpose", "")).strip_edges() == "":
			errors.append("Case %s does not state its playtest purpose." % case_id)
		if not (case_def.get("acceptance_focus", []) is Array) or (case_def.get("acceptance_focus", []) as Array).is_empty():
			errors.append("Case %s has no acceptance focus." % case_id)
		if case_def.has("play_config"):
			_validate_play_config(case_def.get("play_config", {}), "Case %s play_config" % case_id, errors)
	return {"valid": errors.is_empty(), "errors": errors}


static func _validate_play_config(raw: Variant, label: String, errors: Array[String]) -> void:
	if not (raw is Dictionary):
		errors.append("%s must be an object." % label)
		return
	var play_config := raw as Dictionary
	if play_config.is_empty():
		return
	var food_test := str(play_config.get("food_test", "neutral"))
	if not VALID_FOOD_TESTS.has(food_test):
		errors.append("%s has invalid food_test '%s'." % [label, food_test])
	var game_mode := str(play_config.get("game_mode", GAME_MODE_BY_FOOD_TEST.get(food_test, "neutral")))
	if not FOOD_TEST_BY_GAME_MODE.has(game_mode):
		errors.append("%s has invalid game_mode '%s'." % [label, game_mode])
	elif play_config.has("food_test") and FOOD_TEST_BY_GAME_MODE[game_mode] != food_test:
		errors.append(
			"%s mixes game_mode '%s' with food_test '%s'. These must describe the same economy."
			% [label, game_mode, food_test]
		)
	var food_settings: Variant = play_config.get("food_test_settings", {})
	if not (food_settings is Dictionary):
		errors.append("%s food_test_settings must be an object." % label)
		return
	if float((food_settings as Dictionary).get("drain_interval_seconds", 60.0)) < 5.0:
		errors.append("%s drain interval must be at least 5 seconds." % label)
	if float((food_settings as Dictionary).get("drain_atp", 1.0)) < 0.0:
		errors.append("%s drain ATP cannot be negative." % label)


static func cases(catalog := {}) -> Array[Dictionary]:
	var source: Dictionary = catalog if catalog is Dictionary and not (catalog as Dictionary).is_empty() else load_catalog()
	var result: Array[Dictionary] = []
	for raw_case in source.get("cases", []):
		if raw_case is Dictionary:
			result.append((raw_case as Dictionary).duplicate(true))
	return result


static func case_by_id(case_id: String, catalog := {}) -> Dictionary:
	for case_def in cases(catalog):
		if str(case_def.get("id", "")) == case_id:
			return case_def
	return {}


static func settings_for_case(case_id: String, seed_override: Variant = null, catalog := {}) -> Dictionary:
	var case_def := case_by_id(case_id, catalog)
	if case_def.is_empty():
		return {}
	var settings := (case_def.get("settings", {}) as Dictionary).duplicate(true)
	var canonical_seed := int(case_def.get("seed", settings.get("seed", 1)))
	var seed := canonical_seed if seed_override == null else int(seed_override)
	settings["seed"] = seed
	if seed != canonical_seed:
		settings["id"] = "%s_variation_%d" % [str(settings.get("id", case_id)), seed]
		settings["title"] = "%s - seed %d" % [str(case_def.get("label", case_id)), seed]
	var world_slot: Dictionary = settings.get("world_slot", {}).duplicate(true)
	world_slot["slot_id"] = str(settings.get("id", case_id))
	world_slot["entry_anchor"] = str(world_slot.get("entry_anchor", "entry"))
	world_slot["exit_anchor"] = str(world_slot.get("exit_anchor", "exit_shelter"))
	world_slot["canonical_party"] = world_slot.get("canonical_party", ["aster", "peris", "endo"])
	world_slot["preview_party_preset"] = str(world_slot.get("preview_party_preset", "full_party_full_health"))
	settings["world_slot"] = world_slot
	return settings


static func play_config_for_case(case_id: String, catalog := {}) -> Dictionary:
	var source: Dictionary = catalog if catalog is Dictionary and not (catalog as Dictionary).is_empty() else load_catalog()
	var play_config: Dictionary = source.get("default_play_config", {}).duplicate(true)
	var case_def := case_by_id(case_id, source)
	var case_override: Variant = case_def.get("play_config", {})
	if case_override is Dictionary:
		play_config.merge(case_override as Dictionary, true)
	# Mode labels and food mechanics are one configuration contract. Normalize the
	# pair so persisted settings cannot describe a different economy than a QA case.
	if play_config.has("food_test"):
		var food_test := str(play_config.get("food_test", "neutral"))
		play_config["game_mode"] = str(GAME_MODE_BY_FOOD_TEST.get(food_test, "neutral"))
	elif play_config.has("game_mode"):
		var game_mode := str(play_config.get("game_mode", "neutral"))
		play_config["food_test"] = str(FOOD_TEST_BY_GAME_MODE.get(game_mode, "neutral"))
	return play_config


static func custom_settings(seed: int, tier := "teaching", progression_stage := -1) -> Dictionary:
	var resolved_tier := tier if VALID_TIERS.has(tier) else "teaching"
	var stage := progression_stage
	if stage < 1:
		stage = int(DEFAULT_STAGE_BY_TIER.get(resolved_tier, 2))
	var spec_id := "generated_custom_%s_%d" % [resolved_tier, seed]
	return {
		"id": spec_id,
		"title": "Custom %s seed %d" % [resolved_tier.capitalize(), seed],
		"seed": seed,
		"complexity_tier": resolved_tier,
		"progression_stage": stage,
		"world_slot": {
			"slot_id": spec_id,
			"act": 1,
			"region": "Generated QA",
			"entry_shelter_id": "shelter_1",
			"exit_shelter_id": "shelter_2",
			"entry_anchor": "entry",
			"exit_anchor": "exit_shelter",
			"canonical_party": ["aster", "peris", "endo"],
			"preview_party_preset": "full_party_full_health",
		},
	}


static func display_name(case_def: Dictionary) -> String:
	return "%s  [%s]  seed %d" % [
		str(case_def.get("label", case_def.get("id", "Seed case"))),
		str(case_def.get("status", "candidate")).to_upper(),
		int(case_def.get("seed", 0)),
	]
