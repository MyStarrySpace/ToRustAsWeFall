extends SceneTree

const StretchGeneratorScript := preload("res://scripts/generation/stretch_generator.gd")

const SPEC_PATHS := [
	"res://data/generated_stretches/generated_chain_nested_poc_shelter_2_to_3.json",
	"res://data/generated_stretches/generated_random_walk_poc_shelter_3_to_4.json",
	"res://data/generated_stretches/generated_event_walk_shelter_4_to_5.json",
	"res://data/generated_stretches/generated_sample_teaching_first_fork.json",
	"res://data/generated_stretches/generated_sample_standard_garden_patrol.json",
	"res://data/generated_stretches/generated_sample_hard_carry_run.json",
	"res://data/generated_stretches/generated_sample_setpiece_containment.json",
	"res://data/generated_stretches/generated_sample_survival_run.json",
]

func _init() -> void:
	var selected_paths: Array = SPEC_PATHS.duplicate()
	for raw_arg in OS.get_cmdline_user_args():
		var arg := str(raw_arg)
		if arg.begins_with("--path="):
			selected_paths = [arg.trim_prefix("--path=")]
	var pending: Array[Dictionary] = []
	for path in selected_paths:
		if not SPEC_PATHS.has(path):
			push_error("Unsupported generated stretch spec path: %s" % path)
			quit(1)
			return
		var existing := _read_persisted_snapshot(path)
		if existing.is_empty():
			push_error("Missing or malformed generated stretch spec: %s" % path)
			quit(1)
			return
		var expected_id: String = str(path).get_file().trim_suffix(".json")
		if str(existing.get("id", "")) != expected_id:
			push_error(
				"Generated stretch id/path mismatch at %s (got %s)"
				% [path, str(existing.get("id", ""))])
			quit(1)
			return
		var settings: Dictionary = existing.get("settings", {})
		if settings.is_empty():
			push_error("Generated stretch spec has no settings block: %s" % path)
			quit(1)
			return
		var regenerated: Dictionary = StretchGeneratorScript.generate(settings)
		if not bool(regenerated.get("success", false)):
			push_error("Failed to regenerate %s: %s" % [path, str(regenerated.get("error", ""))])
			quit(1)
			return
		if str(regenerated.get("id", "")) != expected_id \
				or int(regenerated.get("source", {}).get("seed", -1)) \
					!= int(settings.get("seed", -2)):
			push_error("Regeneration changed the id or deterministic seed for %s" % path)
			quit(1)
			return
		pending.append({"path": path, "spec": regenerated})
	for entry: Dictionary in pending:
		var output_path: String = str(entry.get("path", ""))
		var output_spec: Dictionary = entry.get("spec", {}) as Dictionary
		if not StretchGeneratorScript.save_spec(output_spec, output_path):
			push_error("Failed to save regenerated stretch spec: %s" % output_path)
			quit(1)
			return
		print(
			"Regenerated %s seed=%d integrity=%s content_navigation=%d"
			% [
				output_path,
				int(output_spec.get("source", {}).get("seed", 0)),
				str(output_spec.get("spec_integrity", {}).get("contract_id", "")),
				int(output_spec.get("graybox", {}).get(
					"realized_content_navigation_count", 0)),
			])
	quit()


func _read_persisted_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
