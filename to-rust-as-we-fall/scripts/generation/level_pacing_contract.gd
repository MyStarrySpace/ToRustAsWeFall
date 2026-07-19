class_name LevelPacingContract
extends RefCounted

## Pure validation for authored level-pacing measurements.
##
## The analyzer does not inspect scene trees, advance a scheduler, or read files. Callers provide
## a target dictionary and a measured/authored metrics dictionary, which keeps the contract usable
## from headless probes, editor tooling, generated-level tests, and human-playtest exports alike.

const SCHEMA := "trawf_level_pacing_targets_v1"

const REQUIRED_TARGET_IDS := [
	"aster_sim",
	"peris_sim",
	"tag_day",
	"elevator_and_below",
	"leaving_facility",
	"endo_junction_stretch",
	"channels",
	"stacks",
	"rings",
	"lockout",
	"mother_flure",
	"inflammashunt",
	"ordinary_stretch",
	"mechanic_fragment",
]

const VALID_TARGET_BASES := ["explicit", "operative", "planning"]

const DEFAULT_RULES := {
	"minimum_active_ratio": 0.70,
	"maximum_dead_gap_seconds": 5.0,
	"maximum_single_mode_seconds": 45.0,
	"maximum_category_share_of_minimum": 0.50,
}


static func validate_manifest(manifest: Dictionary) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	if str(manifest.get("schema", "")) != SCHEMA:
		_add_error(errors, "manifest_schema", "Manifest schema must be %s." % SCHEMA, "schema")

	var rules_variant: Variant = manifest.get("rules", null)
	if not rules_variant is Dictionary:
		_add_error(errors, "manifest_rules", "Manifest must contain a rules dictionary.", "rules")
	else:
		_validate_rules(rules_variant as Dictionary, errors)

	var targets_variant: Variant = manifest.get("targets", null)
	if not targets_variant is Array:
		_add_error(errors, "manifest_targets", "Manifest must contain a targets array.", "targets")
		return _make_report(errors, warnings, {"target_count": 0})

	var seen: Dictionary = {}
	var targets: Array = targets_variant as Array
	for index in range(targets.size()):
		var target_variant: Variant = targets[index]
		if not target_variant is Dictionary:
			_add_error(errors, "target_type", "Target at index %d must be a dictionary." % index, "targets[%d]" % index)
			continue
		var target: Dictionary = target_variant as Dictionary
		_validate_target_shape(target, errors, "targets[%d]" % index)
		var target_id := str(target.get("id", ""))
		if target_id.is_empty():
			continue
		if seen.has(target_id):
			_add_error(errors, "target_duplicate", "Target id '%s' appears more than once." % target_id, "targets[%d].id" % index)
		else:
			seen[target_id] = true

	for required_id in REQUIRED_TARGET_IDS:
		if not seen.has(required_id):
			_add_error(errors, "target_missing", "Required pacing target '%s' is missing." % required_id, "targets")
	for target_id in seen:
		if not REQUIRED_TARGET_IDS.has(target_id):
			_add_error(errors, "target_unknown", "Unknown pacing target '%s' is not part of the v1 contract." % target_id, "targets")

	return _make_report(errors, warnings, {"target_count": targets.size()})


static func analyze(target: Dictionary, authored_metrics: Dictionary, rules: Dictionary = {}) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var computed: Dictionary = {}
	var target_path := "target"
	_validate_target_shape(target, errors, target_path)
	var resolved_rules: Dictionary = DEFAULT_RULES.duplicate(true)
	for key in rules:
		resolved_rules[key] = rules[key]
	_validate_rules(resolved_rules, errors)

	var band_variant: Variant = target.get("first_clear_seconds", null)
	if not band_variant is Dictionary:
		return _make_report(errors, warnings, {
			"target_id": str(target.get("id", "")),
			"computed": computed,
		})
	var band: Dictionary = band_variant as Dictionary
	if not _is_number(band.get("minimum", null)) or not _is_number(band.get("maximum", null)):
		return _make_report(errors, warnings, {
			"target_id": str(target.get("id", "")),
			"computed": computed,
		})
	var minimum_seconds := float(band.get("minimum", 0.0))
	var maximum_seconds := float(band.get("maximum", 0.0))

	var active_ok := _require_number(authored_metrics, "meaningful_active_seconds", errors)
	var total_ok := _require_number(authored_metrics, "total_play_seconds", errors)
	var dead_gap_ok := _require_number(authored_metrics, "max_dead_gap_seconds", errors)
	var single_mode_ok := _require_number(authored_metrics, "max_single_mode_seconds", errors)
	var decisions_ok := _require_whole_number(authored_metrics, "decision_count", errors)
	var branches_ok := _require_whole_number(authored_metrics, "branch_count", errors)

	var meaningful_active_seconds := float(authored_metrics.get("meaningful_active_seconds", 0.0))
	var total_play_seconds := float(authored_metrics.get("total_play_seconds", 0.0))
	var max_dead_gap_seconds := float(authored_metrics.get("max_dead_gap_seconds", 0.0))
	var max_single_mode_seconds := float(authored_metrics.get("max_single_mode_seconds", 0.0))
	var decision_count := int(authored_metrics.get("decision_count", 0))
	var branch_count := int(authored_metrics.get("branch_count", 0))

	if active_ok:
		if meaningful_active_seconds < 0.0:
			_add_error(errors, "active_negative", "meaningful_active_seconds cannot be negative.", "meaningful_active_seconds", meaningful_active_seconds, 0.0)
		elif meaningful_active_seconds < minimum_seconds:
			_add_error(errors, "below_duration_band", "Meaningful active play is below the first-clear minimum.", "meaningful_active_seconds", meaningful_active_seconds, minimum_seconds)
		elif meaningful_active_seconds > maximum_seconds:
			_add_error(errors, "above_duration_band", "Meaningful active play is above the first-clear maximum.", "meaningful_active_seconds", meaningful_active_seconds, maximum_seconds)

	if total_ok:
		if total_play_seconds <= 0.0:
			_add_error(errors, "total_nonpositive", "total_play_seconds must be greater than zero.", "total_play_seconds", total_play_seconds, 0.0)
		elif active_ok:
			if meaningful_active_seconds > total_play_seconds:
				_add_error(errors, "active_exceeds_total", "Meaningful active time cannot exceed total play time.", "meaningful_active_seconds", meaningful_active_seconds, total_play_seconds)
			else:
				var active_ratio := meaningful_active_seconds / total_play_seconds
				computed["active_ratio"] = active_ratio
				var minimum_active_ratio := float(resolved_rules.get("minimum_active_ratio", 0.70))
				if active_ratio < minimum_active_ratio:
					_add_error(errors, "active_ratio", "Active play ratio is below the contract minimum.", "active_ratio", active_ratio, minimum_active_ratio)

	if authored_metrics.has("active_ratio"):
		if not _is_number(authored_metrics["active_ratio"]):
			_add_error(errors, "metric_type", "active_ratio must be numeric when supplied.", "active_ratio")
		elif computed.has("active_ratio"):
			var supplied_ratio := float(authored_metrics["active_ratio"])
			if absf(supplied_ratio - float(computed["active_ratio"])) > 0.01:
				_add_error(errors, "active_ratio_mismatch", "Supplied active_ratio does not match active time divided by total time.", "active_ratio", supplied_ratio, float(computed["active_ratio"]))

	if dead_gap_ok:
		var maximum_dead_gap := float(resolved_rules.get("maximum_dead_gap_seconds", 5.0))
		if max_dead_gap_seconds < 0.0:
			_add_error(errors, "dead_gap_negative", "max_dead_gap_seconds cannot be negative.", "max_dead_gap_seconds", max_dead_gap_seconds, 0.0)
		elif max_dead_gap_seconds > maximum_dead_gap:
			_add_error(errors, "dead_gap", "The longest inactive gap exceeds the contract maximum.", "max_dead_gap_seconds", max_dead_gap_seconds, maximum_dead_gap)

	if single_mode_ok:
		var maximum_single_mode := float(resolved_rules.get("maximum_single_mode_seconds", 45.0))
		if max_single_mode_seconds < 0.0:
			_add_error(errors, "single_mode_negative", "max_single_mode_seconds cannot be negative.", "max_single_mode_seconds", max_single_mode_seconds, 0.0)
		elif max_single_mode_seconds > maximum_single_mode:
			_add_error(errors, "single_mode", "One uninterrupted play mode exceeds the contract maximum.", "max_single_mode_seconds", max_single_mode_seconds, maximum_single_mode)

	if decisions_ok:
		var min_decisions := int(target.get("min_decisions", 0))
		if decision_count < min_decisions:
			_add_error(errors, "decisions", "The authored route has too few consequential decisions.", "decision_count", decision_count, min_decisions)
	if branches_ok:
		var min_branches := int(target.get("min_branches", 0))
		if branch_count < min_branches:
			_add_error(errors, "branches", "The authored route has too few route, strategy, or exploration branches.", "branch_count", branch_count, min_branches)

	var categories_variant: Variant = authored_metrics.get("category_seconds", null)
	if not categories_variant is Dictionary:
		_add_error(errors, "categories_missing", "category_seconds must be a dictionary of mutually exclusive active-time buckets.", "category_seconds")
	else:
		var categories: Dictionary = categories_variant as Dictionary
		if categories.is_empty():
			_add_error(errors, "categories_empty", "category_seconds must contain at least one active-time bucket.", "category_seconds")
		var category_total := 0.0
		var category_limit := minimum_seconds * float(resolved_rules.get("maximum_category_share_of_minimum", 0.50))
		computed["category_limit_seconds"] = category_limit
		for category_name in categories:
			var seconds_variant: Variant = categories[category_name]
			if not _is_number(seconds_variant):
				_add_error(errors, "category_type", "Category '%s' must contain a numeric duration." % str(category_name), "category_seconds.%s" % str(category_name))
				continue
			var category_seconds := float(seconds_variant)
			if category_seconds < 0.0:
				_add_error(errors, "category_negative", "Category '%s' cannot have a negative duration." % str(category_name), "category_seconds.%s" % str(category_name), category_seconds, 0.0)
				continue
			category_total += category_seconds
			if category_seconds > category_limit:
				_add_error(errors, "category_concentration", "Category '%s' exceeds 50%% of the target minimum; duration cannot come from one repeated activity." % str(category_name), "category_seconds.%s" % str(category_name), category_seconds, category_limit)
		computed["category_total_seconds"] = category_total
		if active_ok:
			var sum_tolerance := maxf(0.5, meaningful_active_seconds * 0.005)
			computed["category_sum_tolerance_seconds"] = sum_tolerance
			if absf(category_total - meaningful_active_seconds) > sum_tolerance:
				_add_error(errors, "category_sum", "Mutually exclusive category durations must sum to meaningful_active_seconds.", "category_seconds", category_total, meaningful_active_seconds)

	computed["minimum_seconds"] = minimum_seconds
	computed["maximum_seconds"] = maximum_seconds
	return _make_report(errors, warnings, {
		"target_id": str(target.get("id", "")),
		"computed": computed,
	})


static func target_by_id(manifest: Dictionary, target_id: String) -> Dictionary:
	var targets_variant: Variant = manifest.get("targets", [])
	if not targets_variant is Array:
		return {}
	for target_variant in targets_variant as Array:
		if target_variant is Dictionary and str((target_variant as Dictionary).get("id", "")) == target_id:
			return (target_variant as Dictionary).duplicate(true)
	return {}


static func _validate_target_shape(target: Dictionary, errors: Array, path: String) -> void:
	var target_id := str(target.get("id", ""))
	if target_id.is_empty():
		_add_error(errors, "target_id", "Pacing target requires a non-empty id.", "%s.id" % path)
	if str(target.get("label", "")).is_empty():
		_add_error(errors, "target_label", "Pacing target '%s' requires a display label." % target_id, "%s.label" % path)
	var basis := str(target.get("target_basis", ""))
	if not VALID_TARGET_BASES.has(basis):
		_add_error(errors, "target_basis", "Pacing target '%s' must declare explicit, operative, or planning provenance." % target_id, "%s.target_basis" % path)
	if basis in ["explicit", "operative"] and str(target.get("source", "")).is_empty():
		_add_error(errors, "target_source", "Pacing target '%s' requires a source for its %s band." % [target_id, basis], "%s.source" % path)
	if str(target.get("basis_note", "")).is_empty():
		_add_error(errors, "target_basis_note", "Pacing target '%s' requires a basis note." % target_id, "%s.basis_note" % path)

	var band_variant: Variant = target.get("first_clear_seconds", null)
	if not band_variant is Dictionary:
		_add_error(errors, "target_band", "Pacing target '%s' requires a first_clear_seconds dictionary." % target_id, "%s.first_clear_seconds" % path)
	else:
		var band: Dictionary = band_variant as Dictionary
		var minimum_variant: Variant = band.get("minimum", null)
		var maximum_variant: Variant = band.get("maximum", null)
		if not _is_number(minimum_variant) or not _is_number(maximum_variant):
			_add_error(errors, "target_band_type", "Pacing target '%s' needs numeric minimum and maximum seconds." % target_id, "%s.first_clear_seconds" % path)
		else:
			var minimum_seconds := float(minimum_variant)
			var maximum_seconds := float(maximum_variant)
			if minimum_seconds <= 0.0 or maximum_seconds < minimum_seconds:
				_add_error(errors, "target_band_order", "Pacing target '%s' must have 0 < minimum <= maximum." % target_id, "%s.first_clear_seconds" % path)

	_validate_nonnegative_integer(target, "min_decisions", errors, path)
	_validate_nonnegative_integer(target, "min_branches", errors, path)


static func _validate_rules(rules: Dictionary, errors: Array) -> void:
	for field in DEFAULT_RULES:
		if not rules.has(field) or not _is_number(rules[field]):
			_add_error(errors, "rule_type", "Pacing rule '%s' must be numeric." % field, "rules.%s" % field)
	if _is_number(rules.get("minimum_active_ratio", null)):
		var ratio := float(rules["minimum_active_ratio"])
		if ratio <= 0.0 or ratio > 1.0:
			_add_error(errors, "rule_range", "minimum_active_ratio must be in (0, 1].", "rules.minimum_active_ratio")
	if _is_number(rules.get("maximum_category_share_of_minimum", null)):
		var category_share := float(rules["maximum_category_share_of_minimum"])
		if category_share <= 0.0 or category_share > 0.50:
			_add_error(errors, "rule_range", "maximum_category_share_of_minimum must be in (0, 0.50].", "rules.maximum_category_share_of_minimum")
	for field in ["maximum_dead_gap_seconds", "maximum_single_mode_seconds"]:
		if _is_number(rules.get(field, null)) and float(rules[field]) <= 0.0:
			_add_error(errors, "rule_range", "%s must be greater than zero." % field, "rules.%s" % field)


static func _validate_nonnegative_integer(source: Dictionary, field: String, errors: Array, path: String) -> void:
	if not source.has(field) or not _is_number(source[field]):
		_add_error(errors, "target_count_type", "%s must be a whole number." % field, "%s.%s" % [path, field])
		return
	var number := float(source[field])
	if number < 0.0 or number != floorf(number):
		_add_error(errors, "target_count_range", "%s must be a non-negative whole number." % field, "%s.%s" % [path, field])


static func _require_number(source: Dictionary, field: String, errors: Array) -> bool:
	if not source.has(field) or not _is_number(source[field]):
		_add_error(errors, "metric_type", "Authored metric '%s' must be numeric." % field, field)
		return false
	return true


static func _require_whole_number(source: Dictionary, field: String, errors: Array) -> bool:
	if not _require_number(source, field, errors):
		return false
	var number := float(source[field])
	if number < 0.0 or number != floorf(number):
		_add_error(errors, "metric_count", "Authored metric '%s' must be a non-negative whole number." % field, field)
		return false
	return true


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _add_error(
	errors: Array,
	code: String,
	message: String,
	field: String = "",
	actual: Variant = null,
	limit: Variant = null
) -> void:
	var issue := {
		"code": code,
		"message": message,
	}
	if not field.is_empty():
		issue["field"] = field
	if actual != null:
		issue["actual"] = actual
	if limit != null:
		issue["limit"] = limit
	errors.append(issue)


static func _make_report(errors: Array, warnings: Array, extras: Dictionary = {}) -> Dictionary:
	var report := {
		"passed": errors.is_empty(),
		"error_count": errors.size(),
		"warning_count": warnings.size(),
		"errors": errors,
		"warnings": warnings,
	}
	for key in extras:
		report[key] = extras[key]
	return report
