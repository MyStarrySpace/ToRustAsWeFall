class_name GridView
extends Node2D

## Draws the SketchModel top-down: a grid, terrain cells, and objects. Content not on
## the current view level is faded and tinted (orange above / blue below) via
## SketchModel.height_tint, with the view level drawn last so it reads as "on top".

const CELL_SIZE := 48.0

const COLOR_BG := Color(0.07, 0.09, 0.12)
const COLOR_GRID_MINOR := Color(1.0, 1.0, 1.0, 0.05)
const COLOR_GRID_MAJOR := Color(1.0, 1.0, 1.0, 0.10)
const COLOR_AXIS := Color(0.45, 0.55, 0.70, 0.35)
const COLOR_ROOM := Color(0.32, 0.46, 0.42, 1.0)
const COLOR_ROOM_EDGE := Color(0.55, 0.78, 0.68, 0.5)
const COLOR_FLORA := Color(0.33, 0.72, 0.36)
const COLOR_FAUNA := Color(0.88, 0.56, 0.20)
const COLOR_SHELTER := Color(0.36, 0.62, 0.95)
const COLOR_BLOCKIN := Color(0.62, 0.62, 0.70, 0.55)
const COLOR_BLOCKIN_EDGE := Color(0.82, 0.82, 0.92, 0.85)
const COLOR_PREVIEW := Color(1.0, 0.92, 0.4, 0.85)

const MAX_GRID_LINES := 260  # stop drawing fine lines when zoomed way out

var model: SketchModel
var view_level := 0
var show_level_layer := true
var show_objects_layer := true
var preview: Dictionary = {}

func set_model(next: SketchModel) -> void:
	model = next
	queue_redraw()

func set_view_level(level: int) -> void:
	view_level = level
	queue_redraw()

func set_layer_visibility(level_layer: bool, objects_layer: bool) -> void:
	show_level_layer = level_layer
	show_objects_layer = objects_layer
	queue_redraw()

func set_preview(next: Dictionary) -> void:
	preview = next
	queue_redraw()

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / CELL_SIZE), floori(world_pos.y / CELL_SIZE))

func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE)

func _visible_world_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2(-1000, -1000, 2000, 2000)
	var inv := viewport.get_canvas_transform().affine_inverse()
	var size := viewport.get_visible_rect().size
	var corners: Array[Vector2] = [inv * Vector2.ZERO, inv * Vector2(size.x, 0), inv * Vector2(0, size.y), inv * size]
	var top_left := corners[0]
	var bottom_right := corners[0]
	for c in corners:
		top_left = top_left.min(c)
		bottom_right = bottom_right.max(c)
	return Rect2(top_left, bottom_right - top_left)

func _draw() -> void:
	var view := _visible_world_rect()
	draw_rect(view, COLOR_BG, true)
	_draw_grid(view)
	if model == null:
		return
	# Bucket cells and objects by level once, so each level draws from its own slice
	# instead of re-scanning the whole model (O(content), not O(content × levels)).
	var cells_by_level := {}
	for key in model.cells.keys():
		var c: Vector3i = key
		if not cells_by_level.has(c.z):
			cells_by_level[c.z] = []
		cells_by_level[c.z].append(Vector2i(c.x, c.y))
	var objects_by_level := {}
	for obj in model.objects:
		var lv := int(obj.get("level", 0))
		if not objects_by_level.has(lv):
			objects_by_level[lv] = []
		objects_by_level[lv].append(obj)
	# Draw low to high: lower levels sit behind (and read blue), the current level is
	# opaque, higher levels float on top as translucent orange ghosts.
	var levels := model.used_levels()
	levels.sort()
	for level in levels:
		_draw_level(int(level), cells_by_level.get(level, []), objects_by_level.get(level, []))
	_draw_preview()

func _draw_grid(view: Rect2) -> void:
	var x0 := floori(view.position.x / CELL_SIZE)
	var x1 := ceili((view.position.x + view.size.x) / CELL_SIZE)
	var y0 := floori(view.position.y / CELL_SIZE)
	var y1 := ceili((view.position.y + view.size.y) / CELL_SIZE)
	if (x1 - x0) + (y1 - y0) > MAX_GRID_LINES:
		return
	var top := view.position.y
	var bottom := view.position.y + view.size.y
	var left := view.position.x
	var right := view.position.x + view.size.x
	for gx in range(x0, x1 + 1):
		var x := gx * CELL_SIZE
		if gx == 0:
			draw_line(Vector2(x, top), Vector2(x, bottom), COLOR_AXIS, 2.0)
		else:
			draw_line(Vector2(x, top), Vector2(x, bottom), COLOR_GRID_MINOR if gx % 5 != 0 else COLOR_GRID_MAJOR, 1.0)
	for gy in range(y0, y1 + 1):
		var y := gy * CELL_SIZE
		if gy == 0:
			draw_line(Vector2(left, y), Vector2(right, y), COLOR_AXIS, 2.0)
		else:
			draw_line(Vector2(left, y), Vector2(right, y), COLOR_GRID_MINOR if gy % 5 != 0 else COLOR_GRID_MAJOR, 1.0)

func _draw_level(level: int, cell_list: Array, obj_list: Array) -> void:
	var delta := level - view_level
	if show_level_layer:
		for cell in cell_list:
			var rect := Rect2(cell_to_world(cell), Vector2(CELL_SIZE, CELL_SIZE))
			draw_rect(rect.grow(-1.0), SketchModel.height_tint(COLOR_ROOM, delta), true)
			if delta == 0:
				draw_rect(rect.grow(-1.0), COLOR_ROOM_EDGE, false, 1.0)
	if show_objects_layer:
		for obj in obj_list:
			_draw_object(obj, delta)

func _draw_object(obj: Dictionary, delta: int) -> void:
	var base := _object_color(obj)
	var col := SketchModel.height_tint(base, delta)
	var origin := cell_to_world(Vector2i(int(obj.get("x", 0)), int(obj.get("y", 0))))
	match str(obj.get("shape", SketchModel.SHAPE_CELL)):
		SketchModel.SHAPE_RECT:
			var size := Vector2(int(obj.get("w", 1)) * CELL_SIZE, int(obj.get("h", 1)) * CELL_SIZE)
			var rect := Rect2(origin, size)
			draw_rect(rect.grow(-2.0), col, true)
			draw_rect(rect.grow(-2.0), SketchModel.height_tint(COLOR_BLOCKIN_EDGE, delta), false, 2.0)
		SketchModel.SHAPE_CIRCLE:
			var r := float(obj.get("r", 1.0)) * CELL_SIZE
			var center := origin + Vector2(CELL_SIZE, CELL_SIZE) * 0.5
			draw_circle(center, r, col)
			draw_arc(center, r, 0.0, TAU, 48, SketchModel.height_tint(COLOR_BLOCKIN_EDGE, delta), 2.0)
		_:
			_draw_point_object(obj, origin, col, delta)

func _draw_point_object(obj: Dictionary, origin: Vector2, col: Color, delta: int) -> void:
	var center := origin + Vector2(CELL_SIZE, CELL_SIZE) * 0.5
	match str(obj.get("kind", "")):
		SketchModel.KIND_SHELTER:
			# A little house: square body + roof.
			var half := CELL_SIZE * 0.34
			draw_rect(Rect2(center - Vector2(half, half * 0.5), Vector2(half * 2.0, half * 1.5)), col, true)
			var roof := PackedVector2Array([
				center + Vector2(-half * 1.15, -half * 0.5),
				center + Vector2(half * 1.15, -half * 0.5),
				center + Vector2(0.0, -half * 1.5),
			])
			draw_colored_polygon(roof, SketchModel.height_tint(col.lightened(0.15), 0))
		SketchModel.KIND_FAUNA:
			draw_circle(center, CELL_SIZE * 0.26, col)
			draw_circle(center, CELL_SIZE * 0.26, SketchModel.height_tint(COLOR_BLOCKIN_EDGE, delta), false, 1.5)
		_:
			# Flora (and any other point object): a soft leaf-blob.
			draw_circle(center, CELL_SIZE * 0.30, col)

func _object_color(obj: Dictionary) -> Color:
	if obj.has("color") and obj["color"] is Array and (obj["color"] as Array).size() >= 3:
		var c: Array = obj["color"]
		return Color(float(c[0]), float(c[1]), float(c[2]))
	match str(obj.get("kind", "")):
		SketchModel.KIND_FLORA: return COLOR_FLORA
		SketchModel.KIND_FAUNA: return COLOR_FAUNA
		SketchModel.KIND_SHELTER: return COLOR_SHELTER
		SketchModel.KIND_BLOCKIN: return COLOR_BLOCKIN
		_: return COLOR_FLORA

func _draw_preview() -> void:
	if preview.is_empty():
		return
	match str(preview.get("type", "")):
		"rect_cells":
			var a: Vector2i = preview["from"]
			var b: Vector2i = preview["to"]
			var origin := cell_to_world(Vector2i(mini(a.x, b.x), mini(a.y, b.y)))
			var span := Vector2((absi(b.x - a.x) + 1) * CELL_SIZE, (absi(b.y - a.y) + 1) * CELL_SIZE)
			draw_rect(Rect2(origin, span), Color(COLOR_PREVIEW, 0.18), true)
			draw_rect(Rect2(origin, span), COLOR_PREVIEW, false, 2.0)
		"circle":
			var center: Vector2 = preview["center"]
			var r: float = preview["radius"]
			draw_circle(center, r, Color(COLOR_PREVIEW.r, COLOR_PREVIEW.g, COLOR_PREVIEW.b, 0.18))
			draw_arc(center, r, 0.0, TAU, 48, COLOR_PREVIEW, 2.0)
		"cell":
			var cell: Vector2i = preview["cell"]
			var rect := Rect2(cell_to_world(cell), Vector2(CELL_SIZE, CELL_SIZE))
			draw_rect(rect, COLOR_PREVIEW, false, 2.0)
