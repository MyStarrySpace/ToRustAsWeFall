extends CanvasLayer

signal overlay_opened()
signal overlay_closed()

@onready var _root: Control = $OverlayRoot
@onready var _timeline: ItemList = $OverlayRoot/Margin/Shell/Split/TimelinePanel/TimelineBox/Timeline
@onready var _preview: TextureRect = $OverlayRoot/Margin/Shell/Split/DetailPanel/DetailBox/Preview
@onready var _title_label: Label = $OverlayRoot/Margin/Shell/Split/DetailPanel/DetailBox/TitleLabel
@onready var _timestamp_label: Label = $OverlayRoot/Margin/Shell/Split/DetailPanel/DetailBox/TimestampLabel
@onready var _location_label: Label = $OverlayRoot/Margin/Shell/Split/DetailPanel/DetailBox/LocationLabel
@onready var _caption_label: Label = $OverlayRoot/Margin/Shell/Split/DetailPanel/DetailBox/CaptionLabel
@onready var _body_label: RichTextLabel = $OverlayRoot/Margin/Shell/Split/DetailPanel/DetailBox/BodyLabel
@onready var _bookmark_button: Button = $OverlayRoot/Margin/Shell/Split/DetailPanel/DetailBox/Actions/BookmarkButton
@onready var _export_button: Button = $OverlayRoot/Margin/Shell/Split/DetailPanel/DetailBox/Actions/ExportButton
@onready var _close_button: Button = $OverlayRoot/Margin/Shell/Header/CloseButton
@onready var _empty_label: Label = $OverlayRoot/Margin/Shell/Split/DetailPanel/DetailBox/EmptyLabel
@onready var _shortcut_label: Label = $OverlayRoot/Margin/Shell/Header/HeaderText/ShortcutLabel
@onready var _file_dialog: FileDialog = $ExportDialog

var _selected_entry_id := -1
var _pause_depth := 0

func _ready() -> void:
	visible = false
	_refresh_binding_labels()
	_refresh_entries()
	var journal := _engram_journal()
	if journal != null:
		journal.connect("entry_added", _on_journal_changed)
		journal.connect("entry_updated", _on_journal_changed)
		journal.connect("journal_reset", _refresh_entries)

## Key-specific unhandled input runs before the pause menu's generic
## `_unhandled_input`. A visible Engram therefore owns Esc and closes cleanly
## instead of leaving its capture pause active under a newly-opened pause menu.
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if event.is_action_pressed("engram_toggle"):
			if visible:
				close_overlay()
			else:
				open_overlay()
			get_viewport().set_input_as_handled()
			return
		if key_event.keycode == KEY_ESCAPE and visible:
			close_overlay()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("engram_capture") and not visible:
			await _capture_now()
			get_viewport().set_input_as_handled()

func open_overlay() -> void:
	_refresh_binding_labels()
	if not visible:
		visible = true
		_push_capture_pause(true)
		overlay_opened.emit()
	_refresh_entries()

func close_overlay() -> void:
	if not visible:
		return
	visible = false
	_push_capture_pause(false)
	overlay_closed.emit()

func open_overlay_for_entry(entry_id: int = -1) -> void:
	open_overlay()
	if entry_id != -1:
		_select_entry(entry_id)

func _capture_now() -> void:
	var scene_root: Node = get_tree().current_scene
	var journal := _engram_journal()
	if scene_root == null or journal == null:
		return

	_push_capture_pause(true)
	var capture_result: Variant = await journal.call("capture_manual_from_scene", scene_root, [self])
	var entry: Dictionary = capture_result if capture_result is Dictionary else {}
	_push_capture_pause(false)
	if entry.is_empty():
		_show_feedback("Capture failed")
		return
	_show_feedback("Engram entry added")
	_refresh_entries()
	_select_entry(int(entry.get("id", -1)))

func _refresh_entries() -> void:
	_timeline.clear()
	var entries := _journal_entries()
	for entry in entries:
		var timeline_text := _timeline_text(entry)
		_timeline.add_item(timeline_text)
		_timeline.set_item_metadata(_timeline.get_item_count() - 1, int(entry.get("id", -1)))

	if entries.is_empty():
		_selected_entry_id = -1
		_show_empty_state()
		return

	var last_selected: int = _selected_entry_id if _selected_entry_id != -1 else int(entries[entries.size() - 1].get("id", -1))
	_select_entry(last_selected)

func _timeline_text(entry: Dictionary) -> String:
	var timestamp: Dictionary = entry.get("timestamp", {})
	var location: Dictionary = entry.get("location", {})
	var bookmark: String = "*" if bool(entry.get("player_bookmark", false)) else " "
	var tag := "L" if str(entry.get("entry_type", "capture")) == "log" else "M"
	var time_text: String = str(timestamp.get("label", "Unknown"))
	var zone_text: String = str(location.get("zone", "Unknown"))
	return "[%s%s] %s - %s" % [tag, bookmark, time_text, zone_text]

func _select_entry(entry_id: int) -> void:
	var entries := _journal_entries()
	for index in range(entries.size()):
		var entry_id_at_index := int(entries[index].get("id", -1))
		if entry_id_at_index == entry_id:
			_timeline.select(index)
			_show_entry(entries[index])
			return
	if not entries.is_empty():
		_timeline.select(entries.size() - 1)
		_show_entry(entries[entries.size() - 1])

func _show_empty_state() -> void:
	_title_label.text = "No Captures Yet"
	_preview.texture = null
	_empty_label.text = "No entries yet. Press %s during play to record the current frame." % _capture_binding_label()
	_empty_label.visible = true
	_timestamp_label.text = ""
	_location_label.text = ""
	_caption_label.text = ""
	_body_label.text = ""
	_body_label.visible = false
	_bookmark_button.disabled = true
	_export_button.disabled = true

func _capture_binding_label() -> String:
	return InputHints.label_for_action("engram_capture", "F8")

func _toggle_binding_label() -> String:
	return InputHints.label_for_action("engram_toggle", "F9")

func _refresh_binding_labels() -> void:
	if _shortcut_label != null:
		_shortcut_label.text = "%s open/close   %s capture" % [
			_toggle_binding_label(),
			_capture_binding_label(),
		]

func _show_entry(entry: Dictionary) -> void:
	_selected_entry_id = int(entry.get("id", -1))
	var journal := _engram_journal()
	if journal != null:
		journal.call("mark_viewed", _selected_entry_id)

	var entry_type := str(entry.get("entry_type", "capture"))
	var timestamp: Dictionary = entry.get("timestamp", {})
	var location: Dictionary = entry.get("location", {})
	var title := str(entry.get("title", ""))
	_title_label.text = title if title != "" else "Entry %04d" % _selected_entry_id
	_timestamp_label.text = "Timestamp: %s" % str(timestamp.get("label", "Unknown"))
	var sub_zone := str(location.get("sub_zone", ""))
	_location_label.text = "Location: %s%s" % [
		str(location.get("zone", "Unknown")),
		(" / " + sub_zone) if sub_zone != "" else ""
	]
	_caption_label.text = "Caption: %s" % str(entry.get("caption", ""))
	_bookmark_button.disabled = false
	_export_button.disabled = entry_type == "log"
	_bookmark_button.text = "Unbookmark" if bool(entry.get("player_bookmark", false)) else "Bookmark"
	if entry_type == "log":
		_preview.texture = null
		_empty_label.text = "Maintenance Log"
		_empty_label.visible = true
		_body_label.text = str(entry.get("body", ""))
		_body_label.visible = _body_label.text != ""
		return
	_empty_label.visible = false
	_body_label.text = ""
	_body_label.visible = false
	_preview.texture = _load_entry_texture(entry)
	if _preview.texture == null:
		_empty_label.text = "Image unavailable"
		_empty_label.visible = true

func _load_entry_texture(entry: Dictionary) -> Texture2D:
	var image_path: String = str(entry.get("image_path", ""))
	if image_path == "":
		return null
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(image_path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _on_item_selected(index: int) -> void:
	var entry_id := int(_timeline.get_item_metadata(index))
	_select_entry(entry_id)

func _toggle_bookmark() -> void:
	if _selected_entry_id == -1:
		return
	var journal := _engram_journal()
	if journal == null:
		return
	journal.call("toggle_bookmark", _selected_entry_id)
	_refresh_entries()
	_select_entry(_selected_entry_id)

func _open_export_dialog() -> void:
	if _selected_entry_id == -1:
		return
	var entry := _journal_entry(_selected_entry_id)
	if str(entry.get("entry_type", "capture")) == "log":
		return
	_file_dialog.current_file = "engram_capture_%04d.png" % _selected_entry_id
	_file_dialog.popup_centered_ratio(0.7)

func _export_selected_capture(path: String) -> void:
	if _selected_entry_id == -1:
		return
	var journal := _engram_journal()
	if journal != null and bool(journal.call("export_capture", _selected_entry_id, path)):
		_show_feedback("Capture exported")
	else:
		_show_feedback("Export failed")

func _engram_journal() -> Node:
	return get_node_or_null("/root/EngramJournal")

func _journal_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var journal := _engram_journal()
	if journal == null:
		return result
	var entries: Variant = journal.call("get_entries")
	if entries is Array:
		for entry in entries:
			if entry is Dictionary:
				result.append(entry)
	return result

func _journal_entry(entry_id: int) -> Dictionary:
	var journal := _engram_journal()
	if journal == null:
		return {}
	var entry: Variant = journal.call("get_entry", entry_id)
	return entry if entry is Dictionary else {}

func _push_capture_pause(active: bool) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null or not scene_root.has_method("set_capture_pause"):
		return
	if active:
		_pause_depth += 1
		scene_root.set_capture_pause(true)
		return
	if _pause_depth > 0:
		_pause_depth -= 1
	if _pause_depth == 0:
		scene_root.set_capture_pause(false)

func _show_feedback(text: String) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root != null and scene_root.has_method("show_capture_message"):
		scene_root.show_capture_message(text)

func _on_journal_changed(_entry_id: int = -1) -> void:
	_refresh_entries()
