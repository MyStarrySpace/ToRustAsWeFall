extends Node

## Central production-backed pacing gate.
##
## Unlike check_level_pacing.gd's analyzer self-test, this verifier asks the real
## production scene scripts for their canonical first-clear contracts. It does
## keeps pure owners outside SceneTree. Aster/Peris need their authored marker
## transforms, and Survival needs the preview host's real run speed, so only those
## three receive a bounded six/eight-frame scene boot. No route is played and no
## scheduler is advanced by the verifier.
##
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     res://tools/verify_production_level_pacing.tscn

const PacingContract := preload("res://scripts/generation/level_pacing_contract.gd")
const MANIFEST_PATH := "res://data/pacing/level_targets.json"

# Several targets share one production host. The owner cache ensures that each
# PackedScene is instantiated only once, and none of the instances enter SceneTree.
const CONTRACT_SOURCES := [
	{
		"target_id": "aster_sim",
		"scene": "res://scenes/tutorial/aster_sim.tscn",
		"method": "get_playtime_contract",
		"tree_boot_frames": 6,
		"pre_tree_properties": {"suppress_scene_change": true},
	},
	{
		"target_id": "peris_sim",
		"scene": "res://scenes/tutorial/peris_sim.tscn",
		"method": "get_playtime_contract",
		"tree_boot_frames": 6,
		"pre_tree_properties": {"suppress_scene_change": true, "start_phase": 1},
	},
	{
		"target_id": "elevator_and_below",
		"scene": "res://scenes/tutorial/elevator.tscn",
		"method": "get_playtime_contract",
	},
	{
		"target_id": "leaving_facility",
		"scene": "res://scenes/tutorial/leaving_facility.tscn",
		"method": "get_playtime_contract",
	},
	{
		"target_id": "ordinary_stretch",
		"scene": "res://scenes/fragments/fragment_preview.tscn",
		"preview_chunk": "survival_range",
		"method": "get_pacing_contract",
		"tree_boot_frames": 8,
	},
	# Inflammashunt is intentionally covered by verify_inflammashunt_longform.gd.
	# Its 7-9 minute figure is a suggested human first-play target whose reasoning,
	# exploration, and recoverable-error time cannot be derived from authored dwell
	# without fabricating padding.
	# Endo Junction and Mother Flure are likewise covered by their focused
	# mechanical verifiers. Their first-clear bands depend on human observation,
	# route synthesis, and recoverable errors, so this production gate must not
	# manufacture fixed "reasoning" seconds to make them fit the manifest.
	# Channels is covered by verify_channels_longform_extension.gd for the same
	# reason: its hydraulic predictions, encounter failures, and route reading need
	# observed first-play telemetry rather than a synthetic 20-30 minute total.
	# Stacks and Rings are covered by their focused structural/sequence verifiers.
	# Their planning bands are hypotheses for human first-clear testing, not a
	# mandate to reintroduce dwell timers or mandatory interaction ladders.
	# Tag Day and Lockout are similarly covered by real-input/sequence regressions.
	# Neither scene exposes a synthetic elapsed-time contract: their optional
	# observation, chase pressure, and player mistakes must be measured in play.
]

var _failures: Array[String] = []
var _owners: Dictionary = {}
var _owner_roots: Dictionary = {}
var _audited_target_ids: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Peris's production contract prices authored dialogue through DialogueData.
	# Loading the real locale keeps that estimate production-backed without booting
	# the tutorial or advancing a single scheduler tick.
	DialogueData.load_dir("res://data/dialogue/en/")
	var manifest := _load_manifest()
	if manifest.is_empty():
		_finish()
		return

	var manifest_report: Dictionary = PacingContract.validate_manifest(manifest)
	_expect(bool(manifest_report.get("passed", false)),
		"the production gate uses a valid v1 pacing manifest",
		manifest_report.get("errors", []))
	var rules: Dictionary = manifest.get("rules", {}) as Dictionary

	print("\n=== Production level pacing ===")
	for source_variant in CONTRACT_SOURCES:
		var source: Dictionary = source_variant
		await _verify_source(source, manifest, rules)

	_verify_coverage()
	_dispose_owners()
	_finish()


func _load_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		_fail("pacing manifest opens", FileAccess.get_open_error())
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("pacing manifest parses as a dictionary", typeof(parsed))
		return {}
	return parsed as Dictionary


func _verify_source(source: Dictionary, manifest: Dictionary, rules: Dictionary) -> void:
	var target_id := str(source.get("target_id", ""))
	var scene_path := str(source.get("scene", ""))
	var method_name := str(source.get("method", ""))
	var target: Dictionary = PacingContract.target_by_id(manifest, target_id)
	_expect(not target.is_empty(), "%s has a manifest target" % target_id)
	if target.is_empty():
		return

	var owner: Node = await _owner_for_source(source)
	_expect(owner != null, "%s production scene instantiates" % target_id, scene_path)
	if owner == null:
		return
	var bounded_tree_boot := int(source.get("tree_boot_frames", 0)) > 0
	_expect(owner.is_inside_tree() == bounded_tree_boot,
		"%s uses its declared minimal scene lifecycle" % target_id)
	_expect(owner.has_method(method_name),
		"%s production owner exposes %s" % [target_id, method_name], scene_path)
	if not owner.has_method(method_name):
		return

	var contract_variant: Variant = owner.call(method_name)
	_expect(contract_variant is Dictionary,
		"%s returns a pacing dictionary" % target_id, typeof(contract_variant))
	if not contract_variant is Dictionary:
		return
	var raw_contract: Dictionary = contract_variant as Dictionary
	_expect(not raw_contract.is_empty(), "%s production contract is non-empty" % target_id)
	if raw_contract.is_empty():
		return

	# Three older production methods use precise, named measurements but predate
	# the analyzer's field names. This adapter only aliases/splits those existing
	# measurements; it never changes their active or elapsed duration.
	var metrics := _canonical_metrics(target_id, raw_contract)
	_verify_production_duration_identity(target_id, raw_contract, metrics)
	var report: Dictionary = PacingContract.analyze(target, metrics, rules)
	_expect(bool(report.get("passed", false)),
		"%s passes LevelPacingContract.analyze" % target_id,
		report.get("errors", []))
	_verify_category_and_ratio_invariants(target_id, target, metrics, rules)
	_audited_target_ids.append(target_id)
	_print_metrics(target_id, metrics, report)


func _owner_for_source(source: Dictionary) -> Node:
	var scene_path := str(source.get("scene", ""))
	var preview_chunk := str(source.get("preview_chunk", ""))
	var owner_key := "%s::%s" % [scene_path, preview_chunk]
	if _owners.has(owner_key):
		return _owners[owner_key] as Node
	var resource := load(scene_path)
	if not resource is PackedScene:
		_fail("production pacing scene loads", scene_path)
		return null
	var scene_root := (resource as PackedScene).instantiate()
	if scene_root == null:
		_fail("production pacing scene instantiates", scene_path)
		return null
	for property_name in (source.get("pre_tree_properties", {}) as Dictionary):
		scene_root.set(str(property_name),
			(source.get("pre_tree_properties", {}) as Dictionary)[property_name])
	if not preview_chunk.is_empty():
		scene_root.set("preview_menu", false)
		scene_root.set("preview_chunk", preview_chunk)
	var tree_boot_frames := int(source.get("tree_boot_frames", 0))
	if tree_boot_frames > 0:
		get_tree().root.add_child(scene_root)
		for _frame in range(tree_boot_frames):
			await get_tree().process_frame
	var owner: Node = scene_root
	if not preview_chunk.is_empty():
		owner = scene_root.get("_active_chunk") as Node
		if owner == null:
			_fail("production preview creates chunk '%s'" % preview_chunk, scene_path)
			scene_root.free()
			return null
	_owners[owner_key] = owner
	_owner_roots[owner_key] = scene_root
	return owner


func _canonical_metrics(target_id: String, raw: Dictionary) -> Dictionary:
	var metrics := raw.duplicate(true)
	match target_id:
		"leaving_facility":
			_canonicalize_leaving(metrics)
	return metrics


func _canonicalize_leaving(metrics: Dictionary) -> void:
	var traversal := float(metrics.get("modeled_traversal_seconds", 0.0))
	var field_work := float(metrics.get("modeled_field_work_seconds", 0.0))
	var seal_work := float(metrics.get("modeled_direct_seal_work_seconds", 0.0))
	# Split the long route into its alternating field and hazard traversal modes.
	# Both halves are exact partitions of the production traversal measurement.
	metrics["category_seconds"] = {
		"field_navigation": traversal * 0.5,
		"hazard_navigation": traversal - traversal * 0.5,
		"specialist_fieldwork": field_work,
		"seal_execution": seal_work,
	}
	# The production schedule's longest non-interactive callback is the 4.0 s
	# second-Iron transition. Its 12.5 s fixed-transition total also upper-bounds
	# every individual presentation mode.
	metrics["max_dead_gap_seconds"] = 4.0
	metrics["max_single_mode_seconds"] = maxf(
		float(metrics.get("modeled_fixed_transition_seconds", 0.0)), 8.0)


func _verify_production_duration_identity(
	target_id: String,
	raw: Dictionary,
	metrics: Dictionary
) -> void:
	var expected_active := float(raw.get("meaningful_active_seconds",
		raw.get("modeled_meaningful_active_seconds", 0.0)))
	var expected_total := float(raw.get("total_play_seconds",
		raw.get("modeled_shortest_first_clear_seconds", 0.0)))
	_expect(is_equal_approx(float(metrics.get("meaningful_active_seconds", -1.0)), expected_active),
		"%s analyzer input preserves production active time" % target_id,
		{"production": expected_active, "analyzed": metrics.get("meaningful_active_seconds")})
	_expect(is_equal_approx(float(metrics.get("total_play_seconds", -1.0)), expected_total),
		"%s analyzer input preserves production elapsed time" % target_id,
		{"production": expected_total, "analyzed": metrics.get("total_play_seconds")})


func _verify_category_and_ratio_invariants(
	target_id: String,
	target: Dictionary,
	metrics: Dictionary,
	rules: Dictionary
) -> void:
	var active := float(metrics.get("meaningful_active_seconds", 0.0))
	var total := float(metrics.get("total_play_seconds", 0.0))
	var ratio := active / maxf(total, 0.001)
	var minimum_ratio := float(rules.get("minimum_active_ratio", 0.70))
	_expect(ratio >= minimum_ratio,
		"%s active ratio meets the production floor" % target_id,
		{"actual": ratio, "minimum": minimum_ratio})
	if metrics.has("active_ratio"):
		_expect(absf(float(metrics["active_ratio"]) - ratio) <= 0.01,
			"%s supplied active ratio matches active / total" % target_id)

	var categories_variant: Variant = metrics.get("category_seconds", null)
	_expect(categories_variant is Dictionary,
		"%s exposes mutually exclusive categories" % target_id)
	if not categories_variant is Dictionary:
		return
	var categories: Dictionary = categories_variant as Dictionary
	var category_sum := 0.0
	var maximum_category := 0.0
	var categories_valid := not categories.is_empty()
	for category_name in categories:
		var value: Variant = categories[category_name]
		if not (value is int or value is float) or float(value) < 0.0:
			categories_valid = false
			continue
		category_sum += float(value)
		maximum_category = maxf(maximum_category, float(value))
	var sum_tolerance := maxf(0.5, active * 0.005)
	_expect(categories_valid and absf(category_sum - active) <= sum_tolerance,
		"%s categories sum to meaningful active time" % target_id,
		{"sum": category_sum, "active": active, "tolerance": sum_tolerance})
	var band: Dictionary = target.get("first_clear_seconds", {}) as Dictionary
	var category_limit := float(band.get("minimum", 0.0)) \
		* float(rules.get("maximum_category_share_of_minimum", 0.50))
	_expect(maximum_category <= category_limit,
		"%s has no dominant padding category" % target_id,
		{"maximum_category": maximum_category, "limit": category_limit})


func _print_metrics(target_id: String, metrics: Dictionary, report: Dictionary) -> void:
	var active := float(metrics.get("meaningful_active_seconds", 0.0))
	var total := float(metrics.get("total_play_seconds", 0.0))
	var categories: Dictionary = metrics.get("category_seconds", {}) as Dictionary
	var maximum_category := 0.0
	for seconds in categories.values():
		maximum_category = maxf(maximum_category, float(seconds))
	print("[PACING] %-22s active %7.1fs | total %7.1fs | %5.1f%% | max cat %6.1fs | d/b %d/%d | %s" % [
		target_id,
		active,
		total,
		active / maxf(total, 0.001) * 100.0,
		maximum_category,
		int(metrics.get("decision_count", 0)),
		int(metrics.get("branch_count", 0)),
		"PASS" if bool(report.get("passed", false)) else "FAIL",
	])


func _verify_coverage() -> void:
	var expected: Array[String] = []
	for source_variant in CONTRACT_SOURCES:
		expected.append(str((source_variant as Dictionary).get("target_id", "")))
	var unique := {}
	for target_id in _audited_target_ids:
		unique[target_id] = true
	_expect(_audited_target_ids.size() == CONTRACT_SOURCES.size(),
		"every configured production target was audited",
		{"expected": CONTRACT_SOURCES.size(), "actual": _audited_target_ids.size()})
	_expect(unique.size() == expected.size(),
		"the production target list contains no duplicates",
		{"expected": expected, "audited": _audited_target_ids})
	for target_id in expected:
		_expect(unique.has(target_id), "%s is covered by the production gate" % target_id)


func _dispose_owners() -> void:
	for root_variant in _owner_roots.values():
		var scene_root := root_variant as Node
		if scene_root != null and is_instance_valid(scene_root):
			scene_root.free()
	_owners.clear()
	_owner_roots.clear()


func _expect(condition: bool, label: String, detail: Variant = null) -> void:
	if condition:
		return
	_fail(label, detail)


func _fail(label: String, detail: Variant = null) -> void:
	_failures.append(label)
	push_error("[FAIL] %s | %s" % [label, str(detail)])


func _finish() -> void:
	if _failures.is_empty():
		print("\nPRODUCTION LEVEL PACING: PASS (%d canonical contracts)" % _audited_target_ids.size())
		get_tree().quit(0)
	else:
		push_error("\nPRODUCTION LEVEL PACING: FAIL (%d checks)" % _failures.size())
		get_tree().quit(1)
