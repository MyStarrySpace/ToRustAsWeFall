extends SceneTree

## Builds a self-contained replay (projected level + spotlight/shadow solution paths)
## for every generated stretch spec and writes it to data/generated_stretches/replays/.
## These replay files are what the in-game replay viewer and the Android level-sketch
## app load to animate the party executing each solution.
##
## Run: ../Godot_v4.6.1-stable_win64_console.exe --headless --path "." \
##        --script res://tools/export_stretch_replays.gd

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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPLAY_DIR))
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
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			push_error("  fail (write): %s" % out_path)
			failed += 1
			continue
		file.store_string(JSON.stringify(replay, "\t"))
		file = null
		exported += 1
		var sol: Array = replay.get("solutions", [])
		print("  OK  %-46s solutions=%d frames=%d -> %s" % [
			spec_id,
			sol.size(),
			(sol[0].get("frames", []) as Array).size() if not sol.is_empty() else 0,
			out_path,
		])
	print("=== Replays exported: %d, failed: %d ===" % [exported, failed])
	quit(1 if failed > 0 else 0)
