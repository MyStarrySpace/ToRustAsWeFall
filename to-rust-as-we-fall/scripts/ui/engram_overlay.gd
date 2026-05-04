extends CanvasLayer

signal overlay_opened()
signal overlay_closed()

var _root: Control
var _timeline: ItemList
var _preview: TextureRect
var _title_label: Label
var _timestamp_label: Label
var _location_label: Label
var _caption_label: Label
var _body_label: RichTextLabel
var _bookmark_button: Button
var _export_button: Button
var _close_button: Button
var _empty_label: Label
var _file_dialog: FileDialog

var _selected_entry_id := -1
var _pause_depth := 0

func _ready() -> void:
	layer = 40
	_build_ui()
	visible = false
	_refresh_entries()
	if EngramJournal != null:
		EngramJournal.entry_added.connect(_on_journal_changed)
		EngramJournal.entry_updated.connect(_on_journal_changed)
		EngramJournal.journal_reset.connect(_refresh_entries)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == EngramJournal.ENGRAM_TOGGLE_KEY:
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
		if key_event.keycode == EngramJournal.MANUAL_CAPTURE_KEY and not visible:
			await _capture_now()
			get_viewport().set_input_as_handled()

func open_overlay() -> void:
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
	if scene_root == null:
		return

	_push_capture_pause(true)
	var entry: Dictionary = await EngramJournal.capture_manual_from_scene(scene_root, [self])
	_push_capture_pause(false)
	if entry.is_empty():
		_show_feedback("Capture failed")
		return
	_show_feedback("Engram entry added")
	_refresh_entries()
	_select_entry(int(entry.get("id", -1)))

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.025, 0.04, 0.92)
	_root.add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	_root.add_child(margin)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	margin.add_child(shell)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	shell.add_child(header)

	var header_text := VBoxContainer.new()
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_text)

	var heading := Label.new()
	heading.text = "ASTER'S ENGRAM"
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color(0.66, 0.8, 0.98))
	header_text.add_child(heading)

	var subheading := Label.new()
	subheading.text = "J open/close   C capture"
	subheading.add_theme_font_size_override("font_size", 11)
	subheading.add_theme_color_override("font_color", Color(0.54, 0.58, 0.66))
	header_text.add_child(subheading)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(close_overlay)
	header.add_child(_close_button)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.add_child(split)

	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(330, 0)
	_apply_panel_style(left_panel)
	split.add_child(left_panel)

	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_box)

	var left_heading := Label.new()
	left_heading.text = "Timeline"
	left_heading.add_theme_font_size_override("font_size", 14)
	left_heading.add_theme_color_override("font_color", Color(0.88, 0.9, 0.95))
	left_box.add_child(left_heading)

	_timeline = ItemList.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.item_selected.connect(_on_item_selected)
	left_box.add_child(_timeline)

	var right_panel := PanelContainer.new()
	_apply_panel_style(right_panel)
	split.add_child(right_panel)

	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 10)
	right_panel.add_child(right_box)

	_title_label = Label.new()
	_title_label.text = "No Capture Selected"
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.95))
	right_box.add_child(_title_label)

	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(0, 360)
	right_box.add_child(_preview)

	_empty_label = Label.new()
	_empty_label.text = "No entries yet. Press C during play to record the current frame."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.add_theme_font_size_override("font_size", 13)
	_empty_label.add_theme_color_override("font_color", Color(0.58, 0.6, 0.68))
	_empty_label.custom_minimum_size = Vector2(0, 120)
	right_box.add_child(_empty_label)

	_timestamp_label = _make_meta_label()
	right_box.add_child(_timestamp_label)

	_location_label = _make_meta_label()
	right_box.add_child(_location_label)

	_caption_label = _make_meta_label()
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_box.add_child(_caption_label)

	_body_label = RichTextLabel.new()
	_body_label.fit_content = true
	_body_label.scroll_active = true
	_body_label.custom_minimum_size = Vector2(0, 140)
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("normal_font_size", 13)
	_body_label.add_theme_color_override("default_color", Color(0.77, 0.79, 0.84))
	_body_label.visible = false
	right_box.add_child(_body_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	right_box.add_child(button_row)

	_bookmark_button = Button.new()
	_bookmark_button.text = "Bookmark"
	_bookmark_button.disabled = true
	_bookmark_button.pressed.connect(_toggle_bookmark)
	button_row.add_child(_bookmark_button)

	_export_button = Button.new()
	_export_button.text = "Export PNG"
	_export_button.disabled = true
	_export_button.pressed.connect(_open_export_dialog)
	button_row.add_child(_export_button)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.filters = PackedStringArray(["*.png ; PNG image"])
	_file_dialog.file_selected.connect(_export_selected_capture)
	add_child(_file_dialog)

func _apply_panel_style(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.96)
	style.border_color = Color(0.18, 0.22, 0.3, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

func _make_meta_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.74, 0.77, 0.84))
	return label

func _refresh_entries() -> void:
	_timeline.clear()
	var entries: Array[Dictionary] = EngramJournal.get_entries()
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
	var entries: Array[Dictionary] = EngramJournal.get_entries()
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
	_empty_label.text = "No entries yet. Press C during play to record the current frame."
	_empty_label.visible = true
	_timestamp_label.text = ""
	_location_label.text = ""
	_caption_label.text = ""
	_body_label.text = ""
	_body_label.visible = false
	_bookmark_button.disabled = true
	_export_button.disabled = true

func _show_entry(entry: Dictionary) -> void:
	_selected_entry_id = int(entry.get("id", -1))
	EngramJournal.mark_viewed(_selected_entry_id)

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
	EngramJournal.toggle_bookmark(_selected_entry_id)
	_refresh_entries()
	_select_entry(_selected_entry_id)

func _open_export_dialog() -> void:
	if _selected_entry_id == -1:
		return
	var entry := EngramJournal.get_entry(_selected_entry_id)
	if str(entry.get("entry_type", "capture")) == "log":
		return
	_file_dialog.current_file = "engram_capture_%04d.png" % _selected_entry_id
	_file_dialog.popup_centered_ratio(0.7)

func _export_selected_capture(path: String) -> void:
	if _selected_entry_id == -1:
		return
	if EngramJournal.export_capture(_selected_entry_id, path):
		_show_feedback("Capture exported")
	else:
		_show_feedback("Export failed")

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
