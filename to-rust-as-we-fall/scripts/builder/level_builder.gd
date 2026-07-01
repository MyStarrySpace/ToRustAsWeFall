extends Node3D

## The LEVEL BUILDER — the game in a builder mode. You paint the walkable floor cell by cell (the same grid the
## game walks), mark risky cells, drop the entry/exit/nodes, then Save it as an ASCII map (data/levels via
## user://levels) or Play it — which boots the level through the SAME generated_stretch chunk the procedural
## levels use, so what you build is exactly what you play. Built procedurally; interchange via GridAscii.

const GridAscii := preload("res://scripts/generation/grid_ascii.gd")
const TILE_DIR := "res://resources/models/elevator/tiles/"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const PREVIEW_SCENE := "res://scenes/fragments/fragment_preview.tscn"
const LEVEL_DIR := "user://levels"

enum Brush { FLOOR, RISK, ENTRY, EXIT, NODE, ERASE }

var _brush: Brush = Brush.FLOOR
var _floor := {}          # Vector2i -> true (walkable)
var _risk := {}           # Vector2i -> true (walkable + risky)
var _nodes := {}          # Vector2i -> true (interior node)
var _entry := Vector2i.ZERO
var _exit := Vector2i.ZERO
var _has_entry := false
var _has_exit := false
var _level_name := "my_level"

var _camera: Camera3D
var _cam_target := Vector3.ZERO
var _cam_size := 22.0
var _visual: Node3D
var _painting := false
var _paint_erase := false
var _status: Label
var _name_edit: LineEdit
var _brush_buttons := {}

func _ready() -> void:
	_build_camera()
	_build_lighting()
	_build_grid_overlay()
	_build_hud()
	# A little starter floor so the canvas isn't blank.
	for x in range(-3, 4):
		for z in range(-2, 3):
			_floor[Vector2i(x, z)] = true
	_entry = Vector2i(-3, 0)
	_has_entry = true
	_exit = Vector2i(3, 0)
	_has_exit = true
	_rebuild_visual()
	_refresh_status()

# --- camera ----------------------------------------------------------------------------------------------------

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _cam_size
	add_child(_camera)
	_place_camera()

func _place_camera() -> void:
	_camera.size = _cam_size
	_camera.position = _cam_target + Vector3(0.0, 30.0, 18.0)
	_camera.look_at(_cam_target, Vector3.UP)

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62.0, -38.0, 0.0)
	sun.light_energy = 1.25
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.05, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)

# --- input / painting ------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_size = maxf(6.0, _cam_size - 2.0)
			_place_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_size = minf(60.0, _cam_size + 2.0)
			_place_camera()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = mb.pressed
			_paint_erase = false
			if mb.pressed:
				_paint_at_mouse(false)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# Right-drag erases (a quick eraser regardless of brush).
			_painting = mb.pressed
			_paint_erase = mb.pressed
			if mb.pressed:
				_paint_at_mouse(true)
	elif event is InputEventMouseMotion and _painting:
		_paint_at_mouse(_paint_erase)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_W: _cam_target.z -= 2.0; _place_camera()
			KEY_S: _cam_target.z += 2.0; _place_camera()
			KEY_A: _cam_target.x -= 2.0; _place_camera()
			KEY_D: _cam_target.x += 2.0; _place_camera()

func _cell_under_mouse() -> Vector2i:
	var vp := get_viewport()
	var mouse := vp.get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
	if hit == null:
		return Vector2i(2147483647, 2147483647)
	return Vector2i(int(floor(hit.x)), int(floor(hit.z)))

func _paint_at_mouse(erase: bool) -> void:
	var cell := _cell_under_mouse()
	if cell.x == 2147483647:
		return
	if erase or _brush == Brush.ERASE:
		_floor.erase(cell)
		_risk.erase(cell)
		_nodes.erase(cell)
		if _has_entry and _entry == cell:
			_has_entry = false
		if _has_exit and _exit == cell:
			_has_exit = false
	else:
		match _brush:
			Brush.FLOOR:
				_floor[cell] = true
				_risk.erase(cell)
			Brush.RISK:
				_floor[cell] = true
				_risk[cell] = true
			Brush.ENTRY:
				_floor[cell] = true
				_entry = cell
				_has_entry = true
			Brush.EXIT:
				_floor[cell] = true
				_exit = cell
				_has_exit = true
			Brush.NODE:
				_floor[cell] = true
				_nodes[cell] = true
	_rebuild_visual()
	_refresh_status()

# --- rendering -------------------------------------------------------------------------------------------------

func _tile_mat(tile: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex = load(TILE_DIR + tile + ".png")
	if tex != null:
		m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _rebuild_visual() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = Node3D.new()
	_visual.name = "BuilderVisual"
	add_child(_visual)
	# Floor tiles (deck / rust for risky).
	var st_floor := SurfaceTool.new()
	st_floor.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_risk := SurfaceTool.new()
	st_risk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_floor := false
	var any_risk := false
	for c in _floor.keys():
		var top := Vector3(c.x + 0.5, 0.0, c.y + 0.5)
		if _risk.has(c):
			_slab(st_risk, top, 0.14)
			any_risk = true
		else:
			_slab(st_floor, top, 0.14)
			any_floor = true
	if any_floor:
		_commit(st_floor, _tile_mat("deck_metal"))
	if any_risk:
		_commit(st_risk, _tile_mat("rust_iron"))
	# Markers.
	if _has_entry:
		_marker(_entry, Color(0.36, 0.91, 0.5))
	if _has_exit:
		_marker(_exit, Color(0.4, 0.7, 1.0))
	for c in _nodes.keys():
		_marker(c, Color(0.95, 0.75, 0.2))

func _slab(st: SurfaceTool, top: Vector3, thick: float) -> void:
	var h := 0.5
	var yt := top.y + 0.02
	var yb := top.y + 0.02 - thick
	var x0 := top.x - h
	var x1 := top.x + h
	var z0 := top.z - h
	var z1 := top.z + h
	var A := Vector3(x0, yt, z0); var B := Vector3(x1, yt, z0); var C := Vector3(x1, yt, z1); var D := Vector3(x0, yt, z1)
	var E := Vector3(x0, yb, z0); var F := Vector3(x1, yb, z0); var G := Vector3(x1, yb, z1); var H := Vector3(x0, yb, z1)
	_t(st, A, C, B, Vector3.UP); _t(st, A, D, C, Vector3.UP)
	_t(st, E, F, G, Vector3.DOWN); _t(st, E, G, H, Vector3.DOWN)
	_t(st, A, B, F, Vector3(0, 0, -1)); _t(st, A, F, E, Vector3(0, 0, -1))
	_t(st, D, H, G, Vector3(0, 0, 1)); _t(st, D, G, C, Vector3(0, 0, 1))
	_t(st, A, E, H, Vector3(-1, 0, 0)); _t(st, A, H, D, Vector3(-1, 0, 0))
	_t(st, B, C, G, Vector3(1, 0, 0)); _t(st, B, G, F, Vector3(1, 0, 0))

func _t(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

func _commit(st: SurfaceTool, mat: Material) -> void:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	_visual.add_child(mi)

func _marker(cell: Vector2i, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.7, 0.7)
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.6
	mi.material_override = m
	mi.position = Vector3(cell.x + 0.5, 0.45, cell.y + 0.5)
	_visual.add_child(mi)

func _build_grid_overlay() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "GridOverlay"
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.36, 0.42, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var r := 40
	for i in range(-r, r + 1):
		im.surface_add_vertex(Vector3(i, -0.01, -r))
		im.surface_add_vertex(Vector3(i, -0.01, r))
		im.surface_add_vertex(Vector3(-r, -0.01, i))
		im.surface_add_vertex(Vector3(r, -0.01, i))
	im.surface_end()
	mi.mesh = im
	add_child(mi)

# --- HUD -------------------------------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var top := HBoxContainer.new()
	top.position = Vector2(16, 12)
	top.add_theme_constant_override("separation", 6)
	layer.add_child(top)
	for spec in [["Floor", Brush.FLOOR], ["Risky", Brush.RISK], ["Entry", Brush.ENTRY], ["Exit", Brush.EXIT], ["Node", Brush.NODE], ["Erase", Brush.ERASE]]:
		var b := Button.new()
		b.text = str(spec[0])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(78, 34)
		b.pressed.connect(_select_brush.bind(spec[1] as Brush))
		top.add_child(b)
		_brush_buttons[spec[1]] = b
	(_brush_buttons[Brush.FLOOR] as Button).button_pressed = true

	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-190, 12)
	right.add_theme_constant_override("separation", 6)
	layer.add_child(right)
	_name_edit = LineEdit.new()
	_name_edit.text = _level_name
	_name_edit.placeholder_text = "level name"
	_name_edit.custom_minimum_size = Vector2(174, 32)
	_name_edit.text_changed.connect(func(t): _level_name = t.strip_edges() if t.strip_edges() != "" else "my_level")
	right.add_child(_name_edit)
	_add_action(right, "Save", _on_save)
	_add_action(right, "Load", _on_load)
	_add_action(right, "Play", _on_play)
	_add_action(right, "Main Menu", _on_menu)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(16, -58)
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.7, 0.78, 0.84))
	layer.add_child(_status)

	var help := Label.new()
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(16, -32)
	help.text = "L-click paint  •  R-click erase  •  wheel zoom  •  WASD pan"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.5, 0.58, 0.66))
	layer.add_child(help)

func _add_action(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(174, 34)
	b.pressed.connect(cb)
	parent.add_child(b)

func _select_brush(brush: Brush) -> void:
	_brush = brush
	for k in _brush_buttons.keys():
		(_brush_buttons[k] as Button).button_pressed = (k == brush)

func _refresh_status() -> void:
	if _status == null:
		return
	_status.text = "cells: %d   risky: %d   nodes: %d   entry: %s   exit: %s   brush: %s" % [
		_floor.size(), _risk.size(), _nodes.size(),
		("yes" if _has_entry else "—"), ("yes" if _has_exit else "—"), Brush.keys()[_brush]]

# --- ASCII interchange -----------------------------------------------------------------------------------------

func to_ascii() -> String:
	if _floor.is_empty():
		return ""
	var minx := 2147483647
	var minz := 2147483647
	var maxx := -2147483647
	var maxz := -2147483647
	for c in _floor.keys():
		minx = mini(minx, c.x); minz = mini(minz, c.y)
		maxx = maxi(maxx, c.x); maxz = maxi(maxz, c.y)
	var lines := []
	for z in range(minz, maxz + 1):
		var row := ""
		for x in range(minx, maxx + 1):
			var c := Vector2i(x, z)
			var ch := " "
			if _floor.has(c):
				ch = "~" if _risk.has(c) else "."
			if _has_entry and c == _entry:
				ch = "E"
			elif _has_exit and c == _exit:
				ch = "X"
			elif _nodes.has(c):
				ch = "o"
			row += ch
		lines.append(row)
	return "\n".join(lines) + "\n"

func from_ascii(text: String) -> void:
	_floor.clear()
	_risk.clear()
	_nodes.clear()
	_has_entry = false
	_has_exit = false
	var z := 0
	for line in text.split("\n"):
		var s := str(line)
		if s.begins_with("Level ") or s.length() == 0:
			continue
		for x in range(s.length()):
			var c := Vector2i(x, z)
			var ch := s[x]
			match ch:
				" ":
					pass
				"~":
					_floor[c] = true
					_risk[c] = true
				"E":
					_floor[c] = true
					_entry = c
					_has_entry = true
				"X":
					_floor[c] = true
					_exit = c
					_has_exit = true
				"o":
					_floor[c] = true
					_nodes[c] = true
				_:
					_floor[c] = true
		z += 1
	_rebuild_visual()
	_refresh_status()

# --- actions ---------------------------------------------------------------------------------------------------

func _level_path() -> String:
	return "%s/%s.txt" % [LEVEL_DIR, _level_name]

func _on_save() -> void:
	DirAccess.make_dir_recursive_absolute(LEVEL_DIR)
	var f := FileAccess.open(_level_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(to_ascii())
		f.close()
		_flash("Saved %s" % _level_path())
	else:
		_flash("Save failed")

func _on_load() -> void:
	var path := _level_path()
	if not FileAccess.file_exists(path):
		# fall back to a bundled sample
		path = "res://data/levels/sample_authored.txt"
	if FileAccess.file_exists(path):
		from_ascii(FileAccess.get_file_as_string(path))
		_flash("Loaded %s" % path)
	else:
		_flash("No level to load")

func _on_play() -> void:
	var ascii := to_ascii()
	if ascii.strip_edges() == "":
		_flash("Paint some floor first")
		return
	var spec: Dictionary = GridAscii.spec_from_ascii(ascii, _level_name, _level_name)
	var scene: PackedScene = load(PREVIEW_SCENE)
	if scene == null:
		return
	var inst := scene.instantiate()
	inst.set("preview_menu", false)
	inst.set("preview_chunk", "generated_stretch")
	inst.set("preview_chunk_config", {"spec": spec})
	get_tree().root.add_child(inst)
	get_tree().current_scene = inst
	queue_free()

func _on_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)

func _flash(msg: String) -> void:
	if _status != null:
		_status.text = msg
