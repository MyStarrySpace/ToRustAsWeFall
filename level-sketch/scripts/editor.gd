extends Control

## Touch-first level-sketch editor. Builds the world (camera + GridView) and UI
## procedurally, routes input (one finger = active tool, two fingers = pan/zoom),
## and drives the SketchModel through the selected tool. Desktop: left-drag = tool,
## wheel = zoom, right-drag = pan (so it's testable without a touchscreen).

const SAVE_PATH := "user://sketches/autosave.json"
# A strip along the bottom where one-finger touches don't draw, so the OS swipe-up /
# menu gestures don't place objects.
const BOTTOM_DEAD_ZONE := 76.0

var model := SketchModel.new()
var _history: SketchHistory
var _world: Node2D
var _camera: CameraRig
var _grid: GridView

var _tool := "room_rect"
var _brush := "seefern"  # paint brush when the Paint tool is active ("room", shelter, or a species id)
var _view_level := 0

# Input state.
var _touches: Dictionary = {}        # touch index -> screen position
var _gesture := ""                   # "" | "tool" | "camera"
var _tool_finger := -1
var _stroke_start_cell := Vector2i.ZERO
var _last_paint_cell := Vector2i(2147483647, 2147483647)
var _painted_stroke := false
var _cam_last_mid := Vector2.ZERO
var _cam_last_dist := 0.0
var _cam_fingers: Array = []         # the two touch indices the camera gesture follows
var _mouse_panning := false

# UI references kept for state sync.
var _level_label: Label
var _status_label: Label
var _top_panel: PanelContainer
var _brush_row: Control
var _layer_level_btn: Button
var _layer_objects_btn: Button
var _undo_btn: Button
var _redo_btn: Button
var _confirm_new: ConfirmationDialog
var _brush_swatch: ColorRect
var _brush_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_world()
	_history = SketchHistory.new(model)
	_build_ui()
	_load_if_present()
	_update_history_buttons()
	_refresh_status()
	if "--shot" in OS.get_cmdline_user_args():
		_capture_preview()

# DEV-ONLY preview capture (run with `-- --shot`); builds a demo sketch and saves a
# screenshot so the renderer can be eyeballed. Stripped before release.
func _capture_preview() -> void:
	_build_demo()
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://preview.png")
	get_tree().quit()

func _build_demo() -> void:
	model.clear()
	model.fill_rect(0, 0, 9, 6, 0, "room")
	model.fill_rect(3, 2, 5, 4, 1, "room")    # a platform one level up
	model.fill_rect(1, 5, 3, 7, -1, "room")   # a pit one level down
	model.add_object({"kind": "seefern", "x": 1, "y": 1, "level": 0})
	model.add_object({"kind": "flure", "x": 2, "y": 1, "level": 0})
	model.add_object({"kind": "techos", "x": 7, "y": 1, "level": 0})
	model.add_object({"kind": "spikers", "x": 7, "y": 5, "level": 0})
	model.add_object({"kind": SketchModel.KIND_SHELTER, "x": 8, "y": 5, "level": 0})
	model.add_object({"kind": SketchModel.KIND_BLOCKIN, "shape": SketchModel.SHAPE_RECT, "x": 5, "y": 0, "w": 3, "h": 2, "level": 0})
	model.add_object({"kind": SketchModel.KIND_BLOCKIN, "shape": SketchModel.SHAPE_CIRCLE, "x": 2, "y": 4, "r": 1.8, "level": 0})
	model.add_object({"kind": "capbage", "x": 4, "y": 3, "level": 1})     # above -> orange-tinted
	model.add_object({"kind": "tanglers", "x": 2, "y": 6, "level": -1})   # below -> blue-tinted
	_grid.set_model(model)
	_grid.set_view_level(0)
	_camera.global_position = Vector2(4.5, 3.5) * GridView.CELL_SIZE
	_camera.zoom = Vector2(0.85, 0.85)
	# Show the Paint brush row in the preview so the species palette is visible.
	_select_tool("paint")

# ------------------------------------------------------------------- World setup

func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_grid = GridView.new()
	_grid.name = "GridView"
	_grid.set_model(model)
	_world.add_child(_grid)
	_camera = CameraRig.new()
	_camera.name = "Camera"
	_world.add_child(_camera)
	_camera.make_current()
	# Center on the origin with a comfortable starting zoom.
	_camera.global_position = Vector2(6.0, 4.0) * GridView.CELL_SIZE
	_camera.zoom = Vector2(0.9, 0.9)

# --------------------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	layer.layer = 1
	add_child(layer)
	var ui_root := Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	# Top bar: a dark panel holding a tools row and a (paint-only) brush row.
	var top_panel := _panel(ui_root)
	_top_panel = top_panel
	var top_vbox := VBoxContainer.new()
	top_vbox.add_theme_constant_override("separation", 6)
	top_panel.add_child(top_vbox)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top_vbox.add_child(top_row)
	var tools_group := ButtonGroup.new()
	_tool_btn(top_row, "Room ▭", "room_rect", tools_group, true)
	_tool_btn(top_row, "Paint", "paint", tools_group, false)
	_tool_btn(top_row, "Erase", "erase", tools_group, false)
	_tool_btn(top_row, "Block ▭", "block_rect", tools_group, false)
	_tool_btn(top_row, "Block ●", "block_circle", tools_group, false)
	_undo_btn = _button(top_row, "Undo", _undo)
	_redo_btn = _button(top_row, "Redo", _redo)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(spacer)
	_button(top_row, " − ", func(): _shift_level(-1))
	_level_label = _label(top_row, "Lvl 0")
	_level_label.custom_minimum_size = Vector2(72, 0)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(top_row, " + ", func(): _shift_level(1))
	_layer_level_btn = _toggle(top_row, "Level", true, func(_on): _set_layers())
	_layer_objects_btn = _toggle(top_row, "Obj", true, func(_on): _set_layers())
	_button(top_row, "New", _on_new_pressed)
	_button(top_row, "Save", _save)
	_button(top_row, "Load", _load_if_present)
	_button(top_row, "Copy", _copy_json)
	_button(top_row, "▶ Replay", func(): get_tree().change_scene_to_file("res://scenes/replay.tscn"))

	var brush_row := HBoxContainer.new()
	brush_row.add_theme_constant_override("separation", 6)
	top_vbox.add_child(brush_row)
	_brush_row = brush_row
	_label(brush_row, "Paint:")
	_brush_btn(brush_row, "Room cell", "room")
	_brush_btn(brush_row, "Shelter", SketchModel.KIND_SHELTER)
	_label(brush_row, "Flora")
	_species_dropdown(brush_row, SpeciesCatalog.all_flora())
	_label(brush_row, "Fauna")
	_species_dropdown(brush_row, SpeciesCatalog.all_fauna())
	# Active-brush indicator (colour swatch + name).
	_brush_swatch = ColorRect.new()
	_brush_swatch.custom_minimum_size = Vector2(26, 26)
	_brush_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_brush_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brush_row.add_child(_brush_swatch)
	_brush_label = _label(brush_row, "")
	_set_brush(_brush)
	brush_row.visible = false

	top_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE)

	# Bottom-right camera controls.
	var cam_panel := _panel(ui_root)
	var cam_row := HBoxContainer.new()
	cam_row.add_theme_constant_override("separation", 6)
	cam_panel.add_child(cam_row)
	_button(cam_row, " − ", func(): _zoom_center(0.8))
	_button(cam_row, " + ", func(): _zoom_center(1.25))
	_button(cam_row, " ⌖ ", _recenter)
	cam_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 10)

	# Bottom dead-zone band: a subtle strip showing where one-finger drawing is ignored
	# (so you can swipe up for system gestures/menus without placing things).
	var dead := ColorRect.new()
	dead.color = Color(0.08, 0.10, 0.14, 0.45)
	dead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(dead)
	dead.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dead.offset_top = -BOTTOM_DEAD_ZONE
	dead.offset_bottom = 0
	var dead_edge := ColorRect.new()  # a faint line marking the top of the dead zone
	dead_edge.color = Color(0.45, 0.55, 0.70, 0.35)
	dead_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(dead_edge)
	dead_edge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dead_edge.offset_top = -BOTTOM_DEAD_ZONE
	dead_edge.offset_bottom = -BOTTOM_DEAD_ZONE + 2.0

	# Status (bottom-left, inside the dead-zone band).
	_status_label = _label(ui_root, "")
	_status_label.add_theme_color_override("font_color", Color(0.72, 0.8, 0.88))
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)

	# Confirmation before clearing the sketch with New.
	_confirm_new = ConfirmationDialog.new()
	_confirm_new.title = "New sketch"
	_confirm_new.dialog_text = "Clear the current sketch and start over?"
	_confirm_new.ok_button_text = "Clear"
	_confirm_new.confirmed.connect(_do_new)
	ui_root.add_child(_confirm_new)

func _panel(parent: Node) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.17, 0.93)
	sb.set_content_margin_all(6)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p

func _style_button(b: Button) -> void:
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE

func _button(parent: Node, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	_style_button(b)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b

func _toggle(parent: Node, text: String, pressed: bool, on_toggle: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = pressed
	_style_button(b)
	b.toggled.connect(on_toggle)
	parent.add_child(b)
	return b

func _tool_btn(parent: Node, text: String, tool_id: String, group: ButtonGroup, pressed: bool) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = pressed
	_style_button(b)
	b.pressed.connect(func(): _select_tool(tool_id))
	parent.add_child(b)

func _brush_btn(parent: Node, text: String, brush_id: String) -> void:
	var b := Button.new()
	b.text = text
	_style_button(b)
	b.pressed.connect(func(): _set_brush(brush_id))
	parent.add_child(b)

## A dropdown of species (flora or fauna); selecting one sets it as the brush.
func _species_dropdown(parent: Node, species: Array) -> OptionButton:
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(0, 50)
	ob.add_theme_font_size_override("font_size", 18)
	ob.focus_mode = Control.FOCUS_NONE
	for i in range(species.size()):
		ob.add_item(str(species[i]["name"]), i)
		ob.set_item_metadata(i, str(species[i]["id"]))
	ob.item_selected.connect(func(idx): _set_brush(str(ob.get_item_metadata(idx))))
	parent.add_child(ob)
	return ob

## Set the active paint brush ("room", shelter, or a species id) and update the UI.
func _set_brush(id: String) -> void:
	_brush = id
	if _brush_swatch != null:
		_brush_swatch.color = _brush_color(id)
	if _brush_label != null:
		_brush_label.text = "→ " + _brush_display(id)

func _brush_color(id: String) -> Color:
	if id == "room":
		return GridView.COLOR_ROOM
	if id == SketchModel.KIND_SHELTER:
		return GridView.COLOR_SHELTER
	return SpeciesCatalog.color_of(id)

func _brush_display(id: String) -> String:
	if id == "room":
		return "Room cell"
	if id == SketchModel.KIND_SHELTER:
		return "Shelter"
	return SpeciesCatalog.display_name(id)

func _label(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

# ----------------------------------------------------------------- UI callbacks

func _select_tool(tool_id: String) -> void:
	_tool = tool_id
	if _brush_row != null:
		_brush_row.visible = tool_id == "paint"
		# Showing the brush row grows the panel; re-fit it so the row isn't clipped.
		if _top_panel != null:
			_top_panel.reset_size()
			_top_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE)
	_refresh_status()

func _shift_level(delta: int) -> void:
	_view_level += delta
	_grid.set_view_level(_view_level)
	if _level_label != null:
		_level_label.text = "Lvl %d" % _view_level
	_refresh_status()

func _set_layers() -> void:
	_grid.set_layer_visibility(_layer_level_btn.button_pressed, _layer_objects_btn.button_pressed)

func _zoom_center(factor: float) -> void:
	_camera.zoom_at(get_viewport_rect().size * 0.5, factor)

func _recenter() -> void:
	_camera.global_position = Vector2(6.0, 4.0) * GridView.CELL_SIZE
	_camera.zoom = Vector2(0.9, 0.9)

func _refresh_status() -> void:
	if _status_label == null:
		return
	_status_label.text = "%s   |   cells %d  objects %d   |   one finger: tool   two fingers: pan/zoom" % [
		_tool, model.cells.size(), model.objects.size()
	]

# -------------------------------------------------------------------- File I/O

func _on_new_pressed() -> void:
	if model.is_empty():
		_do_new()
	else:
		_confirm_new.popup_centered()

func _do_new() -> void:
	model.clear()
	_grid.set_model(model)
	_grid.set_preview({})
	_history.commit()
	_update_history_buttons()
	_refresh_status()

# ----------------------------------------------------------------- Undo / redo

func _undo() -> void:
	if _history.undo():
		_after_history_change()

func _redo() -> void:
	if _history.redo():
		_after_history_change()

func _after_history_change() -> void:
	_grid.set_preview({})
	_grid.queue_redraw()
	_update_history_buttons()
	_refresh_status()

func _update_history_buttons() -> void:
	if _undo_btn != null:
		_undo_btn.disabled = not _history.can_undo()
	if _redo_btn != null:
		_redo_btn.disabled = not _history.can_redo()

func _save() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_PATH.get_base_dir())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(model.to_json())
		f.close()
		_flash_status("Saved %d cells / %d objects" % [model.cells.size(), model.objects.size()])

func _load_if_present(_arg := false) -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	# Mutate the model in place (keep the same object the grid + history reference).
	if parsed is Dictionary:
		model.from_dict(parsed)
	_grid.set_model(model)
	if _history != null:
		_history.reset()
		_update_history_buttons()
	_refresh_status()

func _copy_json() -> void:
	DisplayServer.clipboard_set(model.to_json())
	_flash_status("JSON copied to clipboard")

func _flash_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text

# ----------------------------------------------------------------------- Input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion and _mouse_panning:
		_camera.pan_screen(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed:
		if event.keycode == KEY_Z:
			_redo() if event.shift_pressed else _undo()
		elif event.keycode == KEY_Y:
			_redo()

## True for the bottom strip reserved for OS swipe gestures (no one-finger drawing).
func _in_bottom_dead_zone(pos: Vector2) -> bool:
	return pos.y >= get_viewport_rect().size.y - BOTTOM_DEAD_ZONE

func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			# Skip the tool for touches that start in the bottom dead zone; still track
			# the finger so a second finger can start a pan/zoom from there.
			if not _in_bottom_dead_zone(event.position):
				_begin_tool(event.index, event.position)
		elif _touches.size() == 2:
			_cancel_tool()
			_begin_camera_gesture()
	else:
		if _gesture == "tool" and event.index == _tool_finger:
			_end_tool(event.position)
		_touches.erase(event.index)
		if _gesture == "camera" and event.index in _cam_fingers:
			# A tracked finger lifted: re-pick a pair from the survivors and re-seed so
			# there's no cross-pair jump; otherwise end the gesture.
			if _touches.size() >= 2:
				_cam_fingers = _touches.keys().slice(0, 2)
				_reseed_camera()
			else:
				_gesture = ""
				_cam_fingers = []
		if _touches.is_empty():
			_gesture = ""
			_tool_finger = -1

func _on_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position
	if _gesture == "tool" and event.index == _tool_finger:
		_update_tool(event.position)
	elif _gesture == "camera" and _touches.size() >= 2:
		_update_camera_gesture()

func _on_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_camera.zoom_at(event.position, 1.12)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_camera.zoom_at(event.position, 1.0 / 1.12)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_mouse_panning = event.pressed

# --- Camera gesture (two fingers) ---

func _begin_camera_gesture() -> void:
	_gesture = "camera"
	_cam_fingers = _touches.keys().slice(0, 2)
	_reseed_camera()

## Anchor the gesture's midpoint/spread to the two tracked fingers' current positions,
## so the NEXT delta is measured from here (no jump when the tracked pair changes).
func _reseed_camera() -> void:
	if not _cam_pair_present():
		return
	var p0: Vector2 = _touches[_cam_fingers[0]]
	var p1: Vector2 = _touches[_cam_fingers[1]]
	_cam_last_mid = (p0 + p1) * 0.5
	_cam_last_dist = maxf(1.0, p0.distance_to(p1))

func _update_camera_gesture() -> void:
	if not _cam_pair_present():
		return
	var p0: Vector2 = _touches[_cam_fingers[0]]
	var p1: Vector2 = _touches[_cam_fingers[1]]
	var mid: Vector2 = (p0 + p1) * 0.5
	var dist := maxf(1.0, p0.distance_to(p1))
	_camera.pan_screen(mid - _cam_last_mid)
	_camera.zoom_at(mid, dist / _cam_last_dist)
	_cam_last_mid = mid
	_cam_last_dist = dist

func _cam_pair_present() -> bool:
	return _cam_fingers.size() >= 2 and _touches.has(_cam_fingers[0]) and _touches.has(_cam_fingers[1])

# --- Tool stroke (one finger) ---

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return _camera.screen_to_world(screen_pos)

func _begin_tool(index: int, screen_pos: Vector2) -> void:
	_gesture = "tool"
	_tool_finger = index
	var world := _screen_to_world(screen_pos)
	var cell := _grid.world_to_cell(world)
	_stroke_start_cell = cell
	_last_paint_cell = Vector2i(2147483647, 2147483647)
	_painted_stroke = false
	match _tool:
		"paint", "erase":
			# Defer the first commit so a second finger arriving for pan/zoom cancels the
			# stroke cleanly; a pure tap commits in _end_tool.
			_grid.set_preview({"type": "cell", "cell": cell})
		"room_rect", "block_rect":
			_grid.set_preview({"type": "rect_cells", "from": cell, "to": cell})
		"block_circle":
			_grid.set_preview({"type": "circle", "center": _circle_center(), "radius": 0.0})

func _update_tool(screen_pos: Vector2) -> void:
	var world := _screen_to_world(screen_pos)
	var cell := _grid.world_to_cell(world)
	match _tool:
		"paint", "erase":
			_paint_line(_last_paint_cell, cell)
			_painted_stroke = true
			_grid.set_preview({"type": "cell", "cell": cell})
		"room_rect", "block_rect":
			_grid.set_preview({"type": "rect_cells", "from": _stroke_start_cell, "to": cell})
		"block_circle":
			# Radius is measured from the same point the circle is centred on (the start
			# cell's centre), so the preview matches the committed footprint.
			var r := _circle_center().distance_to(world)
			_grid.set_preview({"type": "circle", "center": _circle_center(), "radius": r})

func _end_tool(screen_pos: Vector2) -> void:
	var world := _screen_to_world(screen_pos)
	var cell := _grid.world_to_cell(world)
	match _tool:
		"paint", "erase":
			# A pure tap (no drag) never went through _update_tool, so commit it here.
			if not _painted_stroke:
				_apply_paint(cell)
		"room_rect":
			model.fill_rect(_stroke_start_cell.x, _stroke_start_cell.y, cell.x, cell.y, _view_level, "room")
		"block_rect":
			var x0 := mini(_stroke_start_cell.x, cell.x)
			var y0 := mini(_stroke_start_cell.y, cell.y)
			model.add_object({
				"kind": SketchModel.KIND_BLOCKIN, "shape": SketchModel.SHAPE_RECT,
				"x": x0, "y": y0,
				"w": absi(cell.x - _stroke_start_cell.x) + 1,
				"h": absi(cell.y - _stroke_start_cell.y) + 1,
				"level": _view_level,
			})
		"block_circle":
			var r_cells := maxf(0.5, _circle_center().distance_to(world) / GridView.CELL_SIZE)
			model.add_object({
				"kind": SketchModel.KIND_BLOCKIN, "shape": SketchModel.SHAPE_CIRCLE,
				"x": _stroke_start_cell.x, "y": _stroke_start_cell.y, "r": r_cells,
				"level": _view_level,
			})
	_gesture = ""
	_tool_finger = -1
	_grid.set_preview({})
	_grid.queue_redraw()
	# One completed tool action = one undo step.
	_history.commit()
	_update_history_buttons()
	_refresh_status()

func _cancel_tool() -> void:
	if _gesture == "tool":
		_grid.set_preview({})
	_gesture = ""
	_tool_finger = -1

func _circle_center() -> Vector2:
	return _grid.cell_to_world(_stroke_start_cell) + Vector2(GridView.CELL_SIZE, GridView.CELL_SIZE) * 0.5

func _apply_paint(cell: Vector2i) -> void:
	if cell == _last_paint_cell:
		return
	_last_paint_cell = cell
	if _tool == "erase":
		var obj := model.object_at(cell.x, cell.y, _view_level)
		if not obj.is_empty():
			model.remove_object(int(obj["id"]))
		else:
			model.erase_cell(cell.x, cell.y, _view_level)
	elif _brush == "room":
		model.set_cell(cell.x, cell.y, _view_level, "room")
	else:
		# Point object (flora / fauna / shelter): one per cell+level.
		if model.object_at(cell.x, cell.y, _view_level).is_empty():
			model.add_object({"kind": _brush, "shape": SketchModel.SHAPE_CELL, "x": cell.x, "y": cell.y, "level": _view_level})
	_grid.queue_redraw()
	_refresh_status()

## Apply the paint/erase brush to every cell on the line between two cells, so a fast
## drag doesn't leave gaps.
func _paint_line(from: Vector2i, to: Vector2i) -> void:
	if from.x == 2147483647:
		_apply_paint(to)
		return
	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	var sx := 1 if to.x > from.x else -1
	var sy := 1 if to.y > from.y else -1
	var err := dx - dy
	var cx := from.x
	var cy := from.y
	while true:
		_apply_paint(Vector2i(cx, cy))
		if cx == to.x and cy == to.y:
			break
		var e2 := err * 2
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy
