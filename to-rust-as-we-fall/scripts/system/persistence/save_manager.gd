extends Node

const SAVE_VERSION := 1
const SAVE_ROOT := "user://saves"
const AUTOSAVE_SLOT := "autosave"
const SLOT_MANIFEST := "manifest.json"
const CAPTURE_DIRNAME := "captures"

var active_slot_id := AUTOSAVE_SLOT

func _ready() -> void:
	ensure_slot_dirs(active_slot_id)

func get_slot_dir(slot_id := active_slot_id) -> String:
	return "%s/%s" % [SAVE_ROOT, slot_id]

func get_capture_dir(slot_id := active_slot_id) -> String:
	return "%s/%s" % [get_slot_dir(slot_id), CAPTURE_DIRNAME]

func get_slot_manifest_path(slot_id := active_slot_id) -> String:
	return "%s/%s" % [get_slot_dir(slot_id), SLOT_MANIFEST]

func ensure_slot_dirs(slot_id := active_slot_id) -> void:
	_ensure_dir(SAVE_ROOT)
	_ensure_dir(get_slot_dir(slot_id))
	_ensure_dir(get_capture_dir(slot_id))

func has_slot(slot_id := active_slot_id) -> bool:
	return FileAccess.file_exists(get_slot_manifest_path(slot_id))

func save_current(reason := "autosave") -> bool:
	ensure_slot_dirs(active_slot_id)
	var payload := build_save_payload(get_tree().current_scene, reason)
	return _write_json(get_slot_manifest_path(active_slot_id), payload)

func build_save_payload(scene_root: Node, reason := "autosave") -> Dictionary:
	var scene_path := ""
	var scene_name := ""
	var scene_state := {}

	if scene_root != null:
		scene_path = scene_root.scene_file_path
		scene_name = scene_root.name
		if scene_root.has_method("build_save_snapshot"):
			scene_state = scene_root.build_save_snapshot()

	return {
		"version": SAVE_VERSION,
		"slot_id": active_slot_id,
		"reason": reason,
		"saved_unix": Time.get_unix_time_from_system(),
		"scene_path": scene_path,
		"scene_name": scene_name,
		"scene_state": scene_state,
		"journal": _get_journal_state(),
	}

func load_slot_payload(slot_id := active_slot_id) -> Dictionary:
	if not has_slot(slot_id):
		return {}
	return _read_json(get_slot_manifest_path(slot_id))

func restore_journal_from_slot(slot_id := active_slot_id) -> void:
	var payload := load_slot_payload(slot_id)
	if payload.is_empty():
		return
	var journal := _engram_journal()
	if journal == null:
		return
	journal.apply_save_state(payload.get("journal", {}))

func clear_slot(slot_id := active_slot_id) -> void:
	var slot_dir := ProjectSettings.globalize_path(get_slot_dir(slot_id))
	if DirAccess.dir_exists_absolute(slot_dir):
		_remove_dir_recursive(slot_dir)
	ensure_slot_dirs(slot_id)

func _get_journal_state() -> Dictionary:
	var journal := _engram_journal()
	if journal == null:
		return {}
	return journal.build_save_state()

func _engram_journal() -> Node:
	return get_node_or_null("/root/EngramJournal")

func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))

func _write_json(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: Could not write %s" % path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	return true

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		push_error("SaveManager: Could not parse %s" % path)
		return {}
	var data: Variant = parser.data
	return data if data is Dictionary else {}

func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var child_abs := path.path_join(entry)
		if dir.current_is_dir():
			_remove_dir_recursive(child_abs)
		else:
			DirAccess.remove_absolute(child_abs)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
