extends Node

signal entry_added(entry_id: int)
signal entry_updated(entry_id: int)
signal journal_reset()

## Capture and journal visibility are driven by the `engram_capture` and
## `engram_toggle` InputMap actions so both shortcuts remain remappable.
const MAX_CAPTURE_EDGE := 1280

var _entries: Array[Dictionary] = []
var _next_id := 1
var _busy := false

func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)

func get_entry_count() -> int:
	return _entries.size()

func get_entry(entry_id: int) -> Dictionary:
	for entry in _entries:
		if int(entry.get("id", -1)) == entry_id:
			return entry.duplicate(true)
	return {}

func get_entry_by_story_key(story_key: String) -> Dictionary:
	if story_key == "":
		return {}
	for entry in _entries:
		if str(entry.get("story_key", "")) == story_key:
			return entry.duplicate(true)
	return {}

func has_entries() -> bool:
	return not _entries.is_empty()

func build_save_state() -> Dictionary:
	return {
		"entries": _entries.duplicate(true),
		"next_id": _next_id,
	}

func apply_save_state(data: Dictionary) -> void:
	_entries.clear()
	var raw_entries: Array = data.get("entries", [])
	for raw_entry in raw_entries:
		if raw_entry is Dictionary:
			_entries.append((raw_entry as Dictionary).duplicate(true))
	_next_id = int(data.get("next_id", _entries.size() + 1))
	journal_reset.emit()

func reset_state(clear_files := false) -> void:
	_entries.clear()
	_next_id = 1
	if clear_files:
		var save_manager := _save_manager()
		if save_manager != null:
			save_manager.clear_slot()
	journal_reset.emit()

func toggle_bookmark(entry_id: int) -> void:
	for entry in _entries:
		if int(entry.get("id", -1)) != entry_id:
			continue
		entry["player_bookmark"] = not bool(entry.get("player_bookmark", false))
		entry_updated.emit(entry_id)
		_autosave("bookmark")
		return

func mark_viewed(entry_id: int) -> void:
	for entry in _entries:
		if int(entry.get("id", -1)) != entry_id:
			continue
		if bool(entry.get("viewed", false)):
			return
		entry["viewed"] = true
		entry_updated.emit(entry_id)
		_autosave("viewed")
		return

func export_capture(entry_id: int, output_path: String) -> bool:
	var entry := get_entry(entry_id)
	if entry.is_empty():
		return false
	var source_path := str(entry.get("image_path", ""))
	if source_path == "":
		return false
	var source_abs := ProjectSettings.globalize_path(source_path)
	var target_abs := ProjectSettings.globalize_path(output_path)
	var target_dir := target_abs.get_base_dir()
	DirAccess.make_dir_recursive_absolute(target_dir)

	var source := FileAccess.open(source_abs, FileAccess.READ)
	if source == null:
		return false
	var target := FileAccess.open(target_abs, FileAccess.WRITE)
	if target == null:
		return false
	target.store_buffer(source.get_buffer(source.get_length()))
	return true

func ensure_story_log_entry(story_key: String, title: String, body: String, context: Dictionary, extra: Dictionary = {}) -> Dictionary:
	if story_key == "":
		return {}
	var existing := get_entry_by_story_key(story_key)
	if not existing.is_empty():
		return existing

	var entry_id := _next_id
	_next_id += 1
	var entry := _build_entry(entry_id, "", context)
	entry["entry_type"] = "log"
	entry["title"] = title if title != "" else "Log Entry"
	entry["body"] = body
	entry["story_key"] = story_key
	entry["manual"] = false
	entry["trigger_type"] = str(extra.get("trigger_type", "story"))
	entry["trigger_context"] = str(extra.get("trigger_context", "story_log"))
	entry["caption"] = str(extra.get("caption", title if title != "" else "Log Entry"))
	entry["attached_data"] = extra.get("attached_data", {})
	entry["viewed"] = bool(extra.get("viewed", false))
	_entries.append(entry)
	entry_added.emit(entry_id)
	_autosave("story_log")
	return entry.duplicate(true)

func create_manual_entry_from_image(image: Image, context: Dictionary) -> Dictionary:
	if image == null:
		return {}
	var working_image: Image = image.duplicate()
	if working_image.is_empty():
		return {}
	if working_image.is_compressed():
		working_image.decompress()
	_prepare_image_for_storage(working_image)

	var entry_id := _next_id
	_next_id += 1
	var image_path := _next_capture_path(entry_id)
	var save_error: int = working_image.save_png(ProjectSettings.globalize_path(image_path))
	if save_error != OK:
		push_error("EngramJournal: Could not save capture %d" % entry_id)
		return {}

	var entry := _build_entry(entry_id, image_path, context)
	_entries.append(entry)
	entry_added.emit(entry_id)
	_autosave("capture")
	return entry.duplicate(true)

func capture_manual_from_scene(scene_root: Node, excluded_nodes: Array = []):
	if _busy:
		return {}
	if scene_root == null:
		return {}

	_busy = true
	var hide_nodes := _collect_capture_hide_nodes(scene_root, excluded_nodes)
	var visibility_state := _set_nodes_visible(hide_nodes, false)

	await get_tree().process_frame
	await get_tree().process_frame

	var image := scene_root.get_viewport().get_texture().get_image()
	_restore_nodes_visibility(visibility_state)
	_busy = false

	if image == null or image.is_empty():
		return {}
	return create_manual_entry_from_image(image, _build_context_from_scene(scene_root))

func _build_context_from_scene(scene_root: Node) -> Dictionary:
	if scene_root != null and scene_root.has_method("get_capture_context"):
		var context: Variant = scene_root.get_capture_context()
		return context if context is Dictionary else {}
	return {
		"scene_path": scene_root.scene_file_path if scene_root != null else "",
		"scene_name": scene_root.name if scene_root != null else "Unknown",
		"act": 0,
		"day": 0,
		"time_of_day": "",
		"timestamp_label": "Unknown Session",
		"location": scene_root.name if scene_root != null else "Unknown",
		"sub_location": "",
		"trigger_context": "manual_capture",
		"position": Vector3.ZERO,
		"caption": scene_root.name if scene_root != null else "Manual capture",
	}

func _prepare_image_for_storage(image: Image) -> void:
	var largest_edge := maxi(image.get_width(), image.get_height())
	if largest_edge > MAX_CAPTURE_EDGE:
		var scale := float(MAX_CAPTURE_EDGE) / float(largest_edge)
		image.resize(
			maxi(1, int(roundf(float(image.get_width()) * scale))),
			maxi(1, int(roundf(float(image.get_height()) * scale)))
		)
	image.adjust_bcs(1.0, 1.05, 1.0)

func _next_capture_path(entry_id: int) -> String:
	var save_manager := _save_manager()
	var capture_dir := "user://captures"
	if save_manager != null:
		capture_dir = save_manager.get_capture_dir()
		save_manager.ensure_slot_dirs()
	return "%s/capture_%04d.png" % [capture_dir, entry_id]

func _build_entry(entry_id: int, image_path: String, context: Dictionary) -> Dictionary:
	var position: Vector3 = context.get("position", Vector3.ZERO)
	return {
		"id": entry_id,
		"entry_type": str(context.get("entry_type", "capture")),
		"timestamp": {
			"act": int(context.get("act", 0)),
			"day": int(context.get("day", 0)),
			"time_of_day": str(context.get("time_of_day", "")),
			"label": str(context.get("timestamp_label", "")),
		},
		"location": {
			"zone": str(context.get("location", "Unknown")),
			"sub_zone": str(context.get("sub_location", "")),
			"position_vector": [position.x, position.y, position.z],
		},
		"trigger_type": str(context.get("trigger_type", "manual")),
		"trigger_context": str(context.get("trigger_context", "manual_capture")),
		"image_path": image_path,
		"title": str(context.get("title", "")),
		"body": str(context.get("body", "")),
		"caption": str(context.get("caption", "Manual capture")),
		"attached_data": context.get("attached_data", {}),
		"player_bookmark": false,
		"viewed": false,
		"manual": bool(context.get("manual", image_path != "")),
		"scene_path": str(context.get("scene_path", "")),
		"scene_name": str(context.get("scene_name", "")),
		"story_key": str(context.get("story_key", "")),
		"created_unix": Time.get_unix_time_from_system(),
	}

func _collect_capture_hide_nodes(root: Node, excluded_nodes: Array) -> Array:
	var excluded := {}
	for node in excluded_nodes:
		if node is Node:
			excluded[node.get_instance_id()] = true

	var result: Array = []
	_collect_capture_hide_nodes_recursive(root, result, excluded)
	return result

func _collect_capture_hide_nodes_recursive(node: Node, result: Array, excluded: Dictionary) -> void:
	if excluded.has(node.get_instance_id()):
		return
	if node is CanvasLayer:
		result.append(node)
	for child in node.get_children():
		_collect_capture_hide_nodes_recursive(child, result, excluded)

func _set_nodes_visible(nodes: Array, visible: bool) -> Array[Dictionary]:
	var state: Array[Dictionary] = []
	for node in nodes:
		if not (node is CanvasLayer):
			continue
		state.append({
			"node": node,
			"visible": node.visible,
		})
		node.visible = visible
	return state

func _restore_nodes_visibility(state: Array[Dictionary]) -> void:
	for entry in state:
		var node: CanvasLayer = entry.get("node")
		if node != null:
			node.visible = bool(entry.get("visible", true))

func _autosave(reason: String) -> void:
	var save_manager := _save_manager()
	if save_manager != null:
		save_manager.save_current(reason)

func _save_manager() -> Node:
	return get_node_or_null("/root/SaveManager")
