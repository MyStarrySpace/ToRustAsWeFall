extends SceneTree

## Distill hash-verified persona decision traces into a deterministic policy library.
##
## Safe default: an output path is required. The canonical library is overwritten
## only with the explicit --in-place flag.
##
##   godot --headless --path . --script res://tools/distill_persona_decision_library.gd -- \
##     --trace=res://data/playthroughs/decision_traces/basin_dean.jsonl \
##     --output=user://decision_library.preview.json
##
##   godot --headless --path . --script res://tools/distill_persona_decision_library.gd -- \
##     --trace=res://data/playthroughs/decision_traces/basin_dean.jsonl --in-place

const Distiller := preload("res://scripts/testing/persona_decision_library.gd")
const Trace := preload("res://scripts/testing/persona_decision_trace.gd")
const DEFAULT_LIBRARY := "res://data/playthroughs/decision_library.json"


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	if options.has("error"):
		_fail(str(options["error"]))
		return
	var library_path := str(options.get("library", DEFAULT_LIBRARY))
	var output_path := str(options.get("output", ""))
	if bool(options.get("in_place", false)):
		output_path = library_path
	if output_path == "":
		_fail("pass --output=<path>, or --in-place to update the canonical library explicitly")
		return
	if not bool(options.get("in_place", false)):
		var output_path_issues := Distiller.validate_preview_output_path(
			library_path, output_path, DEFAULT_LIBRARY)
		if not output_path_issues.is_empty():
			_fail("preview output path is unsafe: %s" % str(output_path_issues))
			return
	var trace_paths: Array = options.get("traces", [])
	if trace_paths.is_empty() and not bool(options.get("migrate_only", false)):
		_fail("at least one --trace=<jsonl> is required (or use --migrate-only)")
		return
	var library := Distiller.load_library(library_path)
	if library.is_empty() and FileAccess.file_exists(library_path):
		_fail("the existing library is not valid JSON: %s" % library_path)
		return
	var minimum_support := int(options.get("minimum_support",
		Distiller.DEFAULT_MINIMUM_SUPPORT))
	var documents: Array = []
	for raw_trace_path in trace_paths:
		var document: Dictionary = Trace.read_trace(str(raw_trace_path))
		if not bool(document.get("ok", false)):
			_fail("trace integrity failed for %s: %s" % [
				raw_trace_path, str(document.get("errors", []))])
			return
		documents.append(document)
	# Preview output may demonstrate a schema-proven monotonic target refinement.
	# Explicit in-place promotion deliberately keeps the ordinary conflict-rejecting
	# path so a reviewable preview can never silently authorize canonical mutation.
	var updated := Distiller.distill(library, documents, minimum_support) \
		if bool(options.get("in_place", false)) \
		else Distiller.distill_preview(library, documents, minimum_support)
	var saved := Distiller.save_library(output_path, updated)
	if not bool(saved.get("ok", false)):
		_fail(str(saved.get("error", "library write failed")))
		return
	print("[PERSONA_DECISION_DISTILL] PASS nodes=%d eligible=%d rejected=%d output=%s" % [
		(updated.get("nodes", []) as Array).size(),
		int((updated.get("distillation", {}) as Dictionary).get("eligible_node_count", 0)),
		int((updated.get("distillation", {}) as Dictionary).get("rejected_evidence_count", 0)),
		output_path,
	])
	quit(0)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var options := {
		"library": DEFAULT_LIBRARY,
		"output": "",
		"traces": [],
		"in_place": false,
		"migrate_only": false,
		"minimum_support": Distiller.DEFAULT_MINIMUM_SUPPORT,
	}
	for raw_arg in args:
		var arg := str(raw_arg)
		if arg == "--in-place":
			options["in_place"] = true
		elif arg == "--migrate-only":
			options["migrate_only"] = true
		elif arg.begins_with("--library="):
			options["library"] = arg.trim_prefix("--library=")
		elif arg.begins_with("--output="):
			options["output"] = arg.trim_prefix("--output=")
		elif arg.begins_with("--trace="):
			(options["traces"] as Array).append(arg.trim_prefix("--trace="))
		elif arg.begins_with("--minimum-support="):
			var value := arg.trim_prefix("--minimum-support=")
			if not value.is_valid_int() or int(value) < 1:
				return {"error": "--minimum-support must be a positive integer"}
			options["minimum_support"] = int(value)
		else:
			return {"error": "unknown argument: %s" % arg}
	if bool(options["in_place"]) and str(options["output"]) != "":
		return {"error": "use either --output or --in-place, not both"}
	return options


func _fail(message: String) -> void:
	push_error("[PERSONA_DECISION_DISTILL] FAIL: %s" % message)
	quit(1)
