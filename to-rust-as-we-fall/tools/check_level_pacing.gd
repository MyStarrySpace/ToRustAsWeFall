extends Node

## Standalone smoke test and manifest reporter for the level-pacing contract.
##
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     res://tools/check_level_pacing.tscn

const PacingContract := preload("res://scripts/generation/level_pacing_contract.gd")
const MANIFEST_PATH := "res://data/pacing/level_targets.json"

var _failures := 0


func _ready() -> void:
	var manifest := _load_manifest()
	if manifest.is_empty():
		_finish()
		return

	var manifest_report: Dictionary = PacingContract.validate_manifest(manifest)
	_expect(bool(manifest_report.get("passed", false)), "manifest satisfies the v1 schema", manifest_report.get("errors", []))
	_print_manifest(manifest)
	_run_analyzer_self_checks(manifest)
	_finish()


func _load_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		_fail("manifest opens at %s" % MANIFEST_PATH, FileAccess.get_open_error())
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("manifest parses as a JSON dictionary", typeof(parsed))
		return {}
	return parsed as Dictionary


func _run_analyzer_self_checks(manifest: Dictionary) -> void:
	var target: Dictionary = PacingContract.target_by_id(manifest, "ordinary_stretch")
	_expect(not target.is_empty(), "ordinary_stretch target is available to the pure analyzer")
	if target.is_empty():
		return
	var rules: Dictionary = manifest.get("rules", {}) as Dictionary

	var valid_metrics := {
		"meaningful_active_seconds": 210.0,
		"total_play_seconds": 260.0,
		"max_dead_gap_seconds": 4.5,
		"max_single_mode_seconds": 40.0,
		"decision_count": 2,
		"branch_count": 2,
		"category_seconds": {
			"exploration_and_traversal": 80.0,
			"planning_and_decisions": 70.0,
			"interaction_and_hazard_execution": 60.0,
		},
	}
	var valid_report: Dictionary = PacingContract.analyze(target, valid_metrics, rules)
	_expect(bool(valid_report.get("passed", false)), "balanced authored pacing passes", valid_report.get("errors", []))

	var too_short: Dictionary = valid_metrics.duplicate(true)
	too_short["meaningful_active_seconds"] = 170.0
	too_short["total_play_seconds"] = 220.0
	too_short["category_seconds"] = {
		"exploration_and_traversal": 60.0,
		"planning_and_decisions": 55.0,
		"interaction_and_hazard_execution": 55.0,
	}
	_expect_failure(target, too_short, rules, ["below_duration_band"], "a hallway-sized route fails the duration band")

	var wait_padding: Dictionary = valid_metrics.duplicate(true)
	wait_padding["total_play_seconds"] = 320.0
	wait_padding["max_dead_gap_seconds"] = 30.0
	_expect_failure(target, wait_padding, rules, ["active_ratio", "dead_gap"], "idle-wait padding fails active-ratio and dead-gap rules")

	var monologue_padding: Dictionary = valid_metrics.duplicate(true)
	monologue_padding["max_single_mode_seconds"] = 75.0
	_expect_failure(target, monologue_padding, rules, ["single_mode"], "one uninterrupted mode cannot manufacture length")

	var repetition_padding: Dictionary = valid_metrics.duplicate(true)
	repetition_padding["category_seconds"] = {
		"repeated_switches": 100.0,
		"exploration_and_traversal": 60.0,
		"planning_and_decisions": 50.0,
	}
	_expect_failure(target, repetition_padding, rules, ["category_concentration"], "one repeated activity cannot dominate the target minimum")

	var autopilot_padding: Dictionary = valid_metrics.duplicate(true)
	autopilot_padding["decision_count"] = 0
	autopilot_padding["branch_count"] = 0
	_expect_failure(target, autopilot_padding, rules, ["decisions", "branches"], "an autopilot corridor fails decision and branch floors")

	var dishonest_categories: Dictionary = valid_metrics.duplicate(true)
	dishonest_categories["category_seconds"] = {
		"exploration_and_traversal": 70.0,
		"planning_and_decisions": 60.0,
	}
	_expect_failure(target, dishonest_categories, rules, ["category_sum"], "uncategorized active time cannot hide padding")


func _expect_failure(
	target: Dictionary,
	metrics: Dictionary,
	rules: Dictionary,
	required_codes: Array,
	label: String
) -> void:
	var report: Dictionary = PacingContract.analyze(target, metrics, rules)
	var passed := not bool(report.get("passed", true))
	var missing_codes: Array = []
	for code in required_codes:
		if not _has_error_code(report, str(code)):
			missing_codes.append(code)
	passed = passed and missing_codes.is_empty()
	_expect(passed, label, {
		"missing_codes": missing_codes,
		"actual_errors": report.get("errors", []),
	})


func _has_error_code(report: Dictionary, code: String) -> bool:
	for issue_variant in report.get("errors", []):
		if issue_variant is Dictionary and str((issue_variant as Dictionary).get("code", "")) == code:
			return true
	return false


func _print_manifest(manifest: Dictionary) -> void:
	var rules: Dictionary = manifest.get("rules", {}) as Dictionary
	print("\n=== Level pacing targets ===")
	print("schema: %s" % str(manifest.get("schema", "")))
	print("anti-padding: active >= %.0f%% | dead gap <= %.1fs | one mode <= %.1fs | category <= %.0f%% of minimum" % [
		float(rules.get("minimum_active_ratio", 0.0)) * 100.0,
		float(rules.get("maximum_dead_gap_seconds", 0.0)),
		float(rules.get("maximum_single_mode_seconds", 0.0)),
		float(rules.get("maximum_category_share_of_minimum", 0.0)) * 100.0,
	])
	var basis_counts := {"explicit": 0, "operative": 0, "planning": 0}
	for target_variant in manifest.get("targets", []):
		if not target_variant is Dictionary:
			continue
		var target: Dictionary = target_variant as Dictionary
		var band: Dictionary = target.get("first_clear_seconds", {}) as Dictionary
		var basis := str(target.get("target_basis", ""))
		basis_counts[basis] = int(basis_counts.get(basis, 0)) + 1
		print("  %-22s %4.1f-%4.1f min  %-9s decisions >= %d, branches >= %d" % [
			str(target.get("id", "")),
			float(band.get("minimum", 0.0)) / 60.0,
			float(band.get("maximum", 0.0)) / 60.0,
			basis,
			int(target.get("min_decisions", 0)),
			int(target.get("min_branches", 0)),
		])
	print("basis totals: %d explicit, %d operative, %d planning" % [
		int(basis_counts["explicit"]),
		int(basis_counts["operative"]),
		int(basis_counts["planning"]),
	])


func _expect(condition: bool, label: String, detail: Variant = null) -> void:
	if condition:
		print("[PASS] %s" % label)
		return
	_fail(label, detail)


func _fail(label: String, detail: Variant = null) -> void:
	_failures += 1
	push_error("[FAIL] %s | %s" % [label, str(detail)])


func _finish() -> void:
	if _failures == 0:
		print("\nLEVEL PACING CONTRACT: PASS")
		get_tree().quit(0)
	else:
		push_error("\nLEVEL PACING CONTRACT: FAIL (%d checks)" % _failures)
		get_tree().quit(1)
