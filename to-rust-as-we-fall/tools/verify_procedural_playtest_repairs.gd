extends SceneTree

## Regression guard for issues found in the July browser playtest: requested custom
## seeds must survive exported-resource validation, generated architecture must opt
## into safe camera occlusion, regeneration must replace HUD abilities, and physical
## food copy must describe the carry/consume contract truthfully.

const Generator := preload("res://scripts/generation/stretch_generator.gd")
const SeedCatalog := preload("res://scripts/generation/stretch_seed_catalog.gd")
const PreviewScript := preload("res://scripts/fragments/fragment_preview_sequence.gd")
const ChunkScene := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const HudScene := preload("res://scenes/ui/game_hud.tscn")

var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var generated_specs := []
	for case_def in [
		{"seed": 1704, "tier": "teaching"},
		{"seed": 1801, "tier": "standard"},
		{"seed": 1901, "tier": "hard"},
	]:
		var seed := int(case_def["seed"])
		var tier := str(case_def["tier"])
		var spec: Dictionary = Generator.generate(SeedCatalog.custom_settings(seed, tier))
		check(bool(spec.get("success", false)), "%s seed %d generates" % [tier, seed])
		if not bool(spec.get("success", false)):
			continue
		generated_specs.append(spec)
		check(int(spec.get("source", {}).get("seed", 0)) == seed,
			"requested seed %d remains authoritative" % seed)
		check(str(spec.get("source", {}).get("complexity_tier", "")) == tier,
			"requested %s tier remains authoritative" % tier)
		for feature_v in spec.get("spatial_features", []):
			var feature := feature_v as Dictionary
			var scene_path := str(feature.get("scene", ""))
			check(scene_path != "" and ResourceLoader.exists(scene_path),
				"packaged authored feature exists for %s" % str(feature.get("id", "feature")))

	check("generated_stretch" in PreviewScript.PROCEDURAL_OCCLUSION_CHUNKS,
		"generated stretches use shared camera occlusion")
	if not generated_specs.is_empty():
		var chunk := ChunkScene.instantiate()
		chunk.configure_chunk({
			"settings": SeedCatalog.custom_settings(1704, "teaching"),
			"seed": 1704,
			"food_test": "return_loop",
		})
		root.add_child(chunk)
		await process_frame
		await process_frame
		check((chunk.call("get_generation_fallback_state") as Dictionary).is_empty(),
			"valid requested settings do not silently enter fallback")
		check(bool(chunk.get_meta("camera_occlusion_outline_safe_clip", false)),
			"generated dissolve is outline-safe")
		var caches: Array = chunk.get("_branch_caches")
		var physical_cache := {}
		for cache_v in caches:
			var cache := cache_v as Dictionary
			if bool(cache.get("physical_food", false)):
				physical_cache = cache
				break
		check(not physical_cache.is_empty(), "return-loop run materializes a physical food cache")
		if not physical_cache.is_empty():
			var interactable = physical_cache.get("interactable")
			var verb := str(interactable.call("get_action_verb"))
			var preview := str(interactable.call("get_action_preview"))
			check(verb == "TAKE LYSATE", "cache employs the pickup verb instead of promising immediate ATP")
			check("when consumed" in preview and "one hand" in preview,
				"cache preview explains deferred ATP and carry cost")
			check("not direct HP damage" in preview and "R runs at stamina cost" in preview,
				"cache preview distinguishes exposure from damage and names the travel tradeoff")
		chunk.free()

	var hud = HudScene.instantiate()
	root.add_child(hud)
	await process_frame
	hud.call("add_ability", "emp", "EMP", "1", Color(0.3, 0.6, 1.0), "", "aster")
	check((hud.call("get_hud_contract") as Dictionary).get("abilities", {}).size() == 1,
		"HUD registers the current chunk ability")
	hud.call("clear_abilities")
	check((hud.call("get_hud_contract") as Dictionary).get("abilities", {}).is_empty(),
		"HUD clears old chunk abilities before regeneration")
	hud.call("add_ability", "emp", "EMP", "1", Color(0.3, 0.6, 1.0), "", "aster")
	check((hud.call("get_hud_contract") as Dictionary).get("abilities", {}).size() == 1,
		"same ability can be registered cleanly after regeneration")
	hud.free()

	print("PROCEDURAL PLAYTEST REPAIRS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % message)
		return
	failures += 1
	push_error("FAIL: %s" % message)
