extends Control

## Campaign order manager: a draggable hierarchy of acts > regions > groups > stretches.
## Drag items in the tree to reorder / re-nest, or use the toolbar (Add / Up / Down /
## Indent / Outdent / Stage / Delete). Live validation flags broken shelter links, stage
## regressions, branches, and unplaced stretches. Saves the manifest to user://.

const MANIFEST_BUNDLED := "res://campaign/act1_order.json"
const INDEX_BUNDLED := "res://campaign/stretches_index.json"
const SAVE_PATH := "user://campaign/act1_order.json"

const KIND_COLORS := {
	"campaign": Color(0.86, 0.88, 0.95),
	"act": Color(0.96, 0.82, 0.45),
	"region": Color(0.55, 0.82, 0.88),
	"group": Color(0.78, 0.72, 0.94),
	"stretch": Color(0.62, 0.86, 0.66),
}
const SEVERITY_COLORS := {
	"error": Color(0.95, 0.5, 0.48),
	"warning": Color(0.95, 0.82, 0.5),
	"info": Color(0.6, 0.78, 0.86),
}

var _model: CampaignModel
var _index: Array = []
var _known_ids: Array = []

var _tree: CampaignTree
var _validation: RichTextLabel
var _stretch_menu: PopupMenu
var _stretch_menu_ids: Dictionary = {}
var _rename_dialog: AcceptDialog
var _rename_edit: LineEdit
var _pending_select := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_load(false)
	if "--shot" in OS.get_cmdline_user_args():
		_capture_preview()


# DEV-ONLY preview capture (run the campaign scene with `-- --shot`).
func _capture_preview() -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://campaign_preview.png")
	get_tree().quit()


# --------------------------------------------------------------------------- UI

func _build_ui() -> void:
	var root_box := VBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 0)
	add_child(root_box)

	# Top: two tool rows.
	var top := _panel(root_box)
	var top_v := VBoxContainer.new()
	top_v.add_theme_constant_override("separation", 6)
	top.add_child(top_v)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	top_v.add_child(row1)
	var title := Label.new()
	title.text = "Campaign Order"
	title.add_theme_color_override("font_color", Color(0.82, 0.9, 0.96))
	row1.add_child(title)
	_spacer(row1)
	_button(row1, "+ Act", func(): _add("act", "New Act", true))
	_button(row1, "+ Region", func(): _add("region", "New Region", false))
	_button(row1, "+ Group", func(): _add("group", "New Group", false))
	_button(row1, "+ Stretch", _open_stretch_menu)
	_button(row1, "◂ Editor", func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	top_v.add_child(row2)
	_button(row2, "▲ Up", func(): _reorder(-1))
	_button(row2, "▼ Down", func(): _reorder(1))
	_button(row2, "▸ Indent", func(): _arrange("indent"))
	_button(row2, "◂ Outdent", func(): _arrange("outdent"))
	_button(row2, "Stage −", func(): _bump_stage(-1))
	_button(row2, "Stage +", func(): _bump_stage(1))
	_button(row2, "Rename", _rename)
	_button(row2, "Delete", _delete)

	# Middle: the draggable tree.
	_tree = CampaignTree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.hide_root = false
	_tree.allow_reselect = true
	_tree.node_dropped.connect(_on_node_dropped)
	root_box.add_child(_tree)

	# Bottom: validation + file actions.
	var bottom := _panel(root_box)
	var bottom_v := VBoxContainer.new()
	bottom_v.add_theme_constant_override("separation", 6)
	bottom.add_child(bottom_v)
	_validation = RichTextLabel.new()
	_validation.bbcode_enabled = true
	_validation.fit_content = true
	_validation.scroll_active = false
	_validation.custom_minimum_size = Vector2(0, 84)
	bottom_v.add_child(_validation)
	var files := HBoxContainer.new()
	files.add_theme_constant_override("separation", 6)
	bottom_v.add_child(files)
	_button(files, "Save", _save)
	_button(files, "Load", func(): _load(true))
	_button(files, "Copy JSON", _copy)
	_button(files, "Reset to default", func(): _load(false))

	_stretch_menu = PopupMenu.new()
	_stretch_menu.id_pressed.connect(_on_stretch_picked)
	add_child(_stretch_menu)

	_rename_dialog = AcceptDialog.new()
	_rename_dialog.title = "Rename"
	_rename_edit = LineEdit.new()
	_rename_edit.custom_minimum_size = Vector2(320, 0)
	_rename_dialog.add_child(_rename_edit)
	_rename_dialog.register_text_enter(_rename_edit)
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	add_child(_rename_dialog)


func _panel(parent: Node) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.13, 0.96)
	style.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", style)
	parent.add_child(p)
	return p


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _spacer(parent: Node) -> void:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(s)


# -------------------------------------------------------------------- model I/O

func _load(prefer_saved: bool) -> void:
	_index = CampaignModel.load_index(INDEX_BUNDLED)
	_known_ids.clear()
	for s in _index:
		_known_ids.append(str(s.get("spec_id", "")))
	if prefer_saved and FileAccess.file_exists(SAVE_PATH):
		_model = CampaignModel.load_manifest(SAVE_PATH)
	else:
		_model = CampaignModel.load_manifest(MANIFEST_BUNDLED)
	if _model == null or _model.root().is_empty():
		_model = CampaignModel.new()
	_refresh_tree()


func _save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://campaign"))
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(_model.to_json())


func _copy() -> void:
	DisplayServer.clipboard_set(_model.to_json())


# -------------------------------------------------------------------- tree view

func _refresh_tree() -> void:
	_tree.clear()
	var root_item := _tree.create_item()
	_populate(root_item, _model.root())
	if _pending_select != "":
		_select_node(_pending_select)
		_pending_select = ""
	_refresh_validation()


func _populate(item: TreeItem, node: Dictionary) -> void:
	item.set_text(0, _node_label(node))
	item.set_metadata(0, str(node.get("id", "")))
	item.set_custom_color(0, KIND_COLORS.get(str(node.get("kind", "")), Color.WHITE))
	for child in node.get("children", []):
		if child is Dictionary:
			_populate(_tree.create_item(item), child)


func _node_label(node: Dictionary) -> String:
	var kind := str(node.get("kind", ""))
	var title := str(node.get("title", ""))
	if kind == "stretch":
		return "%s   [%s->%s | stage %d]" % [title, node.get("entry", "?"), node.get("exit", "?"), int(node.get("stage", 1))]
	return "[%s] %s" % [kind.to_upper(), title]


func _selected_id() -> String:
	var item := _tree.get_selected()
	return str(item.get_metadata(0)) if item != null else ""


func _select_node(id: String) -> void:
	var item := _find_item(_tree.get_root(), id)
	if item != null:
		item.select(0)
		_tree.scroll_to_item(item)


func _find_item(item: TreeItem, id: String) -> TreeItem:
	if item == null:
		return null
	if str(item.get_metadata(0)) == id:
		return item
	var child := item.get_first_child()
	while child != null:
		var found := _find_item(child, id)
		if found != null:
			return found
		child = child.get_next()
	return null


# --------------------------------------------------------------------- commands

func _target_container() -> String:
	var sid := _selected_id()
	if sid != "":
		var loc := _model.locate(sid)
		if not loc.is_empty():
			if _model.is_container(loc["node"]):
				return sid
			if loc.get("parent") != null:
				return str(loc["parent"].get("id", ""))
	return str(_model.root().get("id", ""))


func _add(kind: String, title: String, under_root: bool) -> void:
	var parent := str(_model.root().get("id", "")) if under_root else _target_container()
	var nid := _model.add_node(parent, kind, title)
	if nid != "":
		_pending_select = nid
		_refresh_tree()


func _open_stretch_menu() -> void:
	_stretch_menu.clear()
	_stretch_menu_ids.clear()
	var placed := _model.placed_spec_ids()
	var idx := 0
	for s in _index:
		if placed.has(str(s.get("spec_id", ""))):
			continue
		_stretch_menu.add_item("%s   [%s · stage %d]" % [s.get("title", ""), s.get("region", ""), int(s.get("stage", 1))], idx)
		_stretch_menu_ids[idx] = s
		idx += 1
	if idx == 0:
		_stretch_menu.add_item("(every stretch is already placed)", 9999)
		_stretch_menu.set_item_disabled(0, true)
	_stretch_menu.reset_size()
	_stretch_menu.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(0, 8)
	_stretch_menu.popup()


func _on_stretch_picked(id: int) -> void:
	if not _stretch_menu_ids.has(id):
		return
	var s: Dictionary = _stretch_menu_ids[id]
	var nid := _model.add_node(_target_container(), "stretch", str(s.get("title", "Stretch")), {
		"spec_id": str(s.get("spec_id", "")),
		"entry": str(s.get("entry", "")),
		"exit": str(s.get("exit", "")),
		"stage": int(s.get("stage", 1)),
		"region": str(s.get("region", "")),
	})
	if nid != "":
		_pending_select = nid
		_refresh_tree()


func _delete() -> void:
	var sid := _selected_id()
	if sid != "" and _model.remove_node(sid):
		_refresh_tree()


func _rename() -> void:
	var sid := _selected_id()
	if sid == "":
		return
	var loc := _model.locate(sid)
	if loc.is_empty():
		return
	_rename_edit.text = str(loc["node"].get("title", ""))
	_rename_dialog.popup_centered()
	_rename_edit.grab_focus()
	_rename_edit.select_all()


func _on_rename_confirmed() -> void:
	var sid := _selected_id()
	if sid != "" and _rename_edit.text.strip_edges() != "":
		_model.rename_node(sid, _rename_edit.text.strip_edges())
		_pending_select = sid
		_refresh_tree()


func _reorder(delta: int) -> void:
	var sid := _selected_id()
	if sid != "" and _model.reorder_sibling(sid, delta):
		_pending_select = sid
		_refresh_tree()


func _arrange(op: String) -> void:
	var sid := _selected_id()
	if sid == "":
		return
	var ok := _model.indent(sid) if op == "indent" else _model.outdent(sid)
	if ok:
		_pending_select = sid
		_refresh_tree()


func _bump_stage(delta: int) -> void:
	var sid := _selected_id()
	if sid == "":
		return
	var loc := _model.locate(sid)
	if loc.is_empty() or str(loc["node"].get("kind", "")) != "stretch":
		return
	_model.set_field(sid, "stage", clampi(int(loc["node"].get("stage", 1)) + delta, 1, 9))
	_pending_select = sid
	_refresh_tree()


func _on_node_dropped(dragged_id: String, target_id: String, section: int) -> void:
	if dragged_id == "" or target_id == "" or dragged_id == target_id or section < -1 or section > 1:
		return  # ignore self-drops and ambiguous (-100 / no-item) sections
	var target := _model.locate(target_id)
	if target.is_empty():
		return
	var ok := false
	if section == 0 and _model.is_container(target["node"]):
		# Onto a container: nest inside — unless it's already the parent (a no-op, not a shove to the end).
		var src := _model.locate(dragged_id)
		if not src.is_empty() and src.get("parent") != null and str(src["parent"].get("id", "")) == target_id:
			return
		ok = _model.move_into(dragged_id, target_id)
	elif section == 0:
		ok = _model.move_after(dragged_id, target_id)  # onto a stretch leaf -> just after it
	elif target.get("parent") == null:
		ok = _model.move_into(dragged_id, target_id)  # above/below the root -> into the root
	elif section < 0:
		ok = _model.move_before(dragged_id, target_id)
	else:
		ok = _model.move_after(dragged_id, target_id)
	if ok:
		_pending_select = dragged_id
		_refresh_tree()


# ------------------------------------------------------------------- validation

func _refresh_validation() -> void:
	var report := _model.validate(_known_ids)
	var lines := []
	lines.append("[b]%d stretches[/b]   ·   [color=#f08078]%d errors[/color]   [color=#f0d080]%d warnings[/color]" % [
		int(report.get("stretch_count", 0)), int(report.get("error_count", 0)), int(report.get("warning_count", 0))])
	var shown := 0
	for it in report.get("issues", []):
		if shown >= 5:
			lines.append("[color=#8090a0]…and %d more[/color]" % ((report.get("issues", []) as Array).size() - shown))
			break
		var col: Color = SEVERITY_COLORS.get(str(it.get("severity", "")), Color.WHITE)
		lines.append("[color=#%s]• %s[/color]" % [col.to_html(false), str(it.get("message", ""))])
		shown += 1
	_validation.text = "\n".join(lines)
