extends SceneTree

## Verifies the maintained seed corpus, or generates/plays one arbitrary seed.
##
## Examples:
##   godot --headless --path . --script res://tools/verify_stretch_seed_corpus.gd
##   godot --headless --path . --script res://tools/verify_stretch_seed_corpus.gd -- --case=random_walk_3117 --play
##   godot --headless --path . --script res://tools/verify_stretch_seed_corpus.gd -- --seed=8128 --tier=standard --play

const StretchSeedCatalogScript := preload("res://scripts/generation/stretch_seed_catalog.gd")
const StretchGeneratorScript := preload("res://scripts/generation/stretch_generator.gd")
const StretchSolutionSolverScript := preload("res://scripts/generation/stretch_solution_solver.gd")
const StretchGenerationPlaytestLoopScript := preload("res://scripts/generation/stretch_generation_playtest_loop.gd")
const PlaythroughAnimationHtmlRendererScript := preload("res://scripts/generation/playthrough_animation_html_renderer.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog: Dictionary = StretchSeedCatalogScript.load_catalog()
	var validation: Dictionary = catalog.get("validation", {})
	if not bool(validation.get("valid", false)):
		for error in validation.get("errors", []):
			push_error(str(error))
		quit(1)
		return

	var args := _arguments()
	var selected_case := str(args.get("case", ""))
	var play_live := bool(args.get("play", false))
	var animation_output := str(args.get("animation", ""))
	if animation_output != "":
		play_live = true
	var jobs: Array[Dictionary] = []
	if args.has("seed"):
		var seed := int(args.get("seed", 1))
		var tier := str(args.get("tier", "teaching"))
		jobs.append({
			"id": "custom_%d" % seed,
			"status": "custom",
			"settings": StretchSeedCatalogScript.custom_settings(seed, tier),
			"play_config": StretchSeedCatalogScript.play_config_for_case("custom", catalog),
		})
	elif selected_case != "":
		var case_def := StretchSeedCatalogScript.case_by_id(selected_case, catalog)
		if case_def.is_empty():
			push_error("Unknown seed case '%s'." % selected_case)
			quit(1)
			return
		jobs.append({
			"id": selected_case,
			"status": str(case_def.get("status", "candidate")),
			"settings": StretchSeedCatalogScript.settings_for_case(selected_case, null, catalog),
			"play_config": StretchSeedCatalogScript.play_config_for_case(selected_case, catalog),
		})
	else:
		for case_def in StretchSeedCatalogScript.cases(catalog):
			jobs.append({
				"id": str(case_def.get("id", "")),
				"status": str(case_def.get("status", "candidate")),
				"settings": StretchSeedCatalogScript.settings_for_case(str(case_def.get("id", "")), null, catalog),
				"play_config": StretchSeedCatalogScript.play_config_for_case(str(case_def.get("id", "")), catalog),
			})
	if animation_output != "" and jobs.size() != 1:
		push_error("--animation requires exactly one --case or --seed job.")
		quit(1)
		return

	var failures := 0
	print("=== Stretch seed corpus: %d case(s), live_play=%s ===" % [jobs.size(), str(play_live)])
	for job in jobs:
		var settings: Dictionary = job.get("settings", {})
		var spec: Dictionary = StretchGeneratorScript.generate(settings)
		if not bool(spec.get("success", false)):
			failures += 1
			push_error("%s seed=%d generation failed: %s" % [
				str(job.get("id", "?")),
				int(settings.get("seed", 0)),
				str(spec.get("validation", spec.get("error", "unknown error"))),
			])
			continue
		var systems: Dictionary = StretchGeneratorScript.validate_systems_contract(spec)
		var solution: Dictionary = StretchSolutionSolverScript.analyze_spec(spec)
		var machine_ok := bool(systems.get("valid", false)) and bool(solution.get("shadow_solvable", false))
		if not machine_ok:
			failures += 1
			push_error("%s seed=%d failed machine contract: systems=%s shadow=%s" % [
				str(job.get("id", "?")),
				int(settings.get("seed", 0)),
				str(systems.get("errors", [])),
				str(solution.get("shadow_solvable", false)),
			])
			continue
		var live_ok := true
		if play_live:
			var loop = StretchGenerationPlaytestLoopScript.new()
			var play_options := {"preview_config": job.get("play_config", {})}
			if animation_output != "":
				play_options["capture_animation"] = true
				play_options["capture_step"] = float(args.get("capture_step", 0.35))
			var playtest: Dictionary = await loop.playtest_spec(
				spec, self, play_options
			)
			live_ok = bool(playtest.get("ok", false))
			if animation_output != "":
				var animation_saved := _write_animation_outputs(animation_output, playtest)
				live_ok = live_ok and animation_saved
			if not live_ok:
				failures += 1
				push_error("%s seed=%d live playtest failed: %s" % [
					str(job.get("id", "?")),
					int(settings.get("seed", 0)),
					str(playtest.get("errors", [])),
				])
		print("  %-30s status=%-9s seed=%5d tier=%-9s mode=%-10s nodes=%2d machine=%s live=%s" % [
			str(job.get("id", "?")),
			str(job.get("status", "candidate")),
			int(settings.get("seed", 0)),
			str(settings.get("complexity_tier", "")),
			str(job.get("play_config", {}).get("food_test", "neutral")),
			(spec.get("nodes", []) as Array).size(),
			str(machine_ok),
			str(live_ok) if play_live else "not-run",
		])
	print("=== Seed corpus complete: %d passed, %d failed ===" % [jobs.size() - failures, failures])
	quit(1 if failures > 0 else 0)


func _write_animation_outputs(output_path: String, playtest: Dictionary) -> bool:
	var absolute_html := (
		ProjectSettings.globalize_path(output_path)
		if output_path.begins_with("res://") or output_path.begins_with("user://")
		else output_path
	)
	DirAccess.make_dir_recursive_absolute(absolute_html.get_base_dir())
	var html_file := FileAccess.open(absolute_html, FileAccess.WRITE)
	if html_file == null:
		push_error("Could not write playthrough animation: %s" % absolute_html)
		return false
	html_file.store_string(PlaythroughAnimationHtmlRendererScript.build_html(playtest))
	html_file = null
	var report_path := absolute_html.get_basename() + ".report.json"
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		push_error("Could not write playthrough report: %s" % report_path)
		return false
	report_file.store_string(JSON.stringify(playtest, "\t"))
	report_file = null
	print("  animation=%s" % absolute_html)
	print("  report=%s" % report_path)
	return true


func _arguments() -> Dictionary:
	var result := {}
	for raw_arg in OS.get_cmdline_user_args():
		var arg := str(raw_arg)
		if arg == "--play":
			result["play"] = true
		elif arg.begins_with("--case="):
			result["case"] = arg.trim_prefix("--case=")
		elif arg.begins_with("--seed="):
			var value := arg.trim_prefix("--seed=")
			if value.is_valid_int():
				result["seed"] = int(value)
		elif arg.begins_with("--tier="):
			result["tier"] = arg.trim_prefix("--tier=")
		elif arg.begins_with("--animation="):
			result["animation"] = arg.trim_prefix("--animation=")
		elif arg.begins_with("--capture-step="):
			result["capture_step"] = float(arg.trim_prefix("--capture-step="))
	return result
