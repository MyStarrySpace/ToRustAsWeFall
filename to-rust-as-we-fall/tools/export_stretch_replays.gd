extends SceneTree

## Builds a self-contained replay (projected level + spotlight/shadow solution paths)
## for every generated stretch spec and writes it to data/generated_stretches/replays/.
## These replay files are what the in-game replay viewer and the Android level-sketch
## app load to animate the party executing each solution.
##
## Run: ../Godot_v4.6.1-stable_win64_console.exe --headless --path "." \
##        --script res://tools/export_stretch_replays.gd
## Export one committed sample without rewriting its peers by appending:
##        -- --id=generated_sample_standard_garden_patrol

const StretchGeneratorScript := preload("res://scripts/generation/stretch_generator.gd")
const StretchReplayBuilderScript := preload("res://scripts/generation/stretch_replay_builder.gd")

const SPEC_DIR := "res://data/generated_stretches"
const REPLAY_DIR := "res://data/generated_stretches/replays"

func _init() -> void:
	var dir := DirAccess.open(SPEC_DIR)
	if dir == null:
		push_error("Cannot open spec dir: %s" % SPEC_DIR)
		quit(1)
		return
	var exported := 0
	var failed := 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	var names := []
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	names = _selected_spec_names(names)
	if names.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPLAY_DIR))
	var repository_root := ProjectSettings.globalize_path("res://") \
		.path_join("..").simplify_path()
	var bundled_replay_dir := repository_root.path_join("level-sketch/samples")
	DirAccess.make_dir_recursive_absolute(bundled_replay_dir)
	print("=== Exporting replays ===")
	for name in names:
		var spec: Dictionary = StretchGeneratorScript.load_spec("%s/%s" % [SPEC_DIR, name])
		if spec.is_empty():
			push_error("  skip (unreadable): %s" % name)
			failed += 1
			continue
		var replay: Dictionary = StretchReplayBuilderScript.build(spec)
		var spec_id := str(spec.get("id", name.get_basename()))
		var out_path := "%s/%s.replay.json" % [REPLAY_DIR, spec_id]
		var bundled_path := bundled_replay_dir.path_join(
			"%s.replay.json" % spec_id)
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		var bundled_file := FileAccess.open(bundled_path, FileAccess.WRITE)
		if file == null or bundled_file == null:
			push_error(
				"  fail (write): game=%s bundled=%s" % [out_path, bundled_path])
			failed += 1
			continue
		var replay_json := JSON.stringify(replay, "\t")
		file.store_string(replay_json)
		bundled_file.store_string(replay_json)
		file = null
		bundled_file = null
		exported += 1
		var sol: Array = replay.get("solutions", [])
		print("  OK  %-46s solutions=%d frames=%d -> %s + %s" % [
			spec_id,
			sol.size(),
			(sol[0].get("frames", []) as Array).size() if not sol.is_empty() else 0,
			out_path,
			bundled_path,
		])
	print("=== Replays exported: %d, failed: %d ===" % [exported, failed])
	quit(1 if failed > 0 else 0)


func _selected_spec_names(names: Array) -> Array:
	var requested_id := ""
	var filter_seen := false
	for arg_v in OS.get_cmdline_user_args():
		var arg := str(arg_v)
		if arg == "--id":
			push_error("Missing value: use --id=<exact generated stretch id>.")
			return []
		if not arg.begins_with("--id="):
			continue
		var candidate := arg.trim_prefix("--id=")
		if candidate.is_empty():
			push_error("Empty --id filter; provide an exact generated stretch id.")
			return []
		if filter_seen and requested_id != candidate:
			push_error("Conflicting --id filters: %s and %s." % [requested_id, candidate])
			return []
		requested_id = candidate
		filter_seen = true
	if not filter_seen:
		return names
	var selected: Array = []
	for name_v in names:
		var name := str(name_v)
		if name.trim_suffix(".json") == requested_id:
			selected.append(name)
	if selected.is_empty():
		push_error("Unknown generated stretch id: %s" % requested_id)
	return selected
