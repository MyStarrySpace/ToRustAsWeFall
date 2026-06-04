class_name ReplayView
extends Node2D

## Draws a generated stretch's flat projection — node pads, routes, placed flora/fauna/
## structures — and the party dots executing the selected solution at the current time.
## Shares the editor's CELL_SIZE and SpeciesCatalog so a replayed level reads like a
## sketched one.

const CELL := 48.0

const COLOR_BG := Color(0.07, 0.09, 0.12)
const COLOR_GRID := Color(1.0, 1.0, 1.0, 0.05)
const COLOR_NODE := Color(0.30, 0.40, 0.52)
const COLOR_NODE_DONE := Color(0.38, 0.62, 0.50)
const COLOR_NODE_CURRENT := Color(0.95, 0.82, 0.42)
const COLOR_LABEL := Color(0.86, 0.91, 0.95)
const COLOR_STRUCT := Color(0.62, 0.66, 0.74)
const COLOR_SHELTER := Color(0.36, 0.62, 0.95)

const ROUTE_COLORS := {
	"safe": Color(0.42, 0.70, 0.52),
	"risky": Color(0.86, 0.42, 0.40),
	"shortcut": Color(0.45, 0.62, 0.95),
}
# Per-character dot colors come from the single roster registry so the replay and the
# Cast screen never drift; CharacterRoster covers all six.

var replay: ReplayData
var solution_index := 0
var time := 0.0

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func set_replay(next: ReplayData) -> void:
	replay = next
	queue_redraw()


func set_solution_index(index: int) -> void:
	solution_index = index
	queue_redraw()


func set_time(t: float) -> void:
	time = t
	queue_redraw()


## World-space center of the level (for the camera to frame on load).
func level_center() -> Vector2:
	var b := _bounds()
	return b.get_center()


func level_size() -> Vector2:
	return _bounds().size


func _bounds() -> Rect2:
	if replay == null:
		return Rect2(-CELL * 4, -CELL * 4, CELL * 8, CELL * 8)
	var nodes: Array = replay.level().get("nodes", [])
	if nodes.is_empty():
		return Rect2(-CELL * 4, -CELL * 4, CELL * 8, CELL * 8)
	var min_c := Vector2(1e20, 1e20)
	var max_c := Vector2(-1e20, -1e20)
	for n in nodes:
		var c := _cell_to_world(_cell(n.get("cell", [0, 0])))
		min_c = min_c.min(c)
		max_c = max_c.max(c)
	return Rect2(min_c - Vector2(CELL, CELL) * 2.0, (max_c - min_c) + Vector2(CELL, CELL) * 4.0)


func _draw() -> void:
	draw_rect(_visible_rect(), COLOR_BG, true)
	if replay == null:
		return
	var level: Dictionary = replay.level()
	var visited := replay.visited_nodes(solution_index, time)
	var current_frame := replay.frame_at(solution_index, time)
	var current_node := str(current_frame.get("node", ""))

	_draw_routes(level.get("routes", []))
	_draw_content(level.get("content", []))
	_draw_nodes(level.get("nodes", []), visited, current_node)
	_draw_characters()


func _draw_routes(routes: Array) -> void:
	for r in routes:
		if not (r is Dictionary):
			continue
		var from_w := _cell_to_world(_cell(r.get("from_cell", [0, 0])))
		var to_w := _cell_to_world(_cell(r.get("to_cell", [0, 0])))
		var color: Color = ROUTE_COLORS.get(str(r.get("kind", "safe")), ROUTE_COLORS["safe"])
		draw_line(from_w, to_w, Color(color, 0.55), 3.0)


func _draw_content(content: Array) -> void:
	for c in content:
		if not (c is Dictionary):
			continue
		var center := _cell_to_world(_cell(c.get("cell", [0, 0]))) + Vector2(CELL, CELL) * 0.32
		var kind := str(c.get("kind", ""))
		var category := SpeciesCatalog.category_of(kind)
		if category == "flora":
			draw_circle(center, CELL * 0.16, SpeciesCatalog.color_of(kind))
		elif category == "fauna":
			draw_circle(center, CELL * 0.15, SpeciesCatalog.color_of(kind))
			draw_arc(center, CELL * 0.15, 0.0, TAU, 16, Color(0.1, 0.1, 0.12, 0.8), 1.5)
		elif kind == "shelter":
			draw_rect(Rect2(center - Vector2(CELL, CELL) * 0.13, Vector2(CELL, CELL) * 0.26), COLOR_SHELTER, true)
		else:
			draw_rect(Rect2(center - Vector2(CELL, CELL) * 0.11, Vector2(CELL, CELL) * 0.22), Color(COLOR_STRUCT, 0.85), true)


func _draw_nodes(nodes: Array, visited: Array, current_node: String) -> void:
	for n in nodes:
		if not (n is Dictionary):
			continue
		var id := str(n.get("id", ""))
		var top_left := _cell_to_world(_cell(n.get("cell", [0, 0]))) - Vector2(CELL, CELL) * 0.5
		var rect := Rect2(top_left, Vector2(CELL, CELL) * 1.0)
		var color := COLOR_NODE
		if id == current_node:
			color = COLOR_NODE_CURRENT
		elif visited.has(id):
			color = COLOR_NODE_DONE
		draw_rect(rect.grow(-3.0), Color(color, 0.85), true)
		draw_rect(rect.grow(-3.0), color.lightened(0.25), false, 2.0)
		if _font != null:
			var label := str(n.get("label", id))
			draw_string(_font, top_left + Vector2(2.0, -6.0), label, HORIZONTAL_ALIGNMENT_LEFT, CELL * 2.2, 13, COLOR_LABEL)


func _draw_characters() -> void:
	if replay == null:
		return
	var chars := replay.characters_at(solution_index, time)
	for id in chars.keys():
		var pos: Vector2 = chars[id]
		var center := _cell_to_world(pos) + Vector2(CELL, CELL) * 0.5
		var color: Color = CharacterRoster.color_of(str(id))
		draw_circle(center, CELL * 0.22, color)
		draw_arc(center, CELL * 0.22, 0.0, TAU, 20, Color(0.05, 0.06, 0.08, 0.9), 2.0)
		if _font != null:
			var initial := str(id).substr(0, 1).to_upper()
			draw_string(_font, center - Vector2(5.0, -5.0), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.06, 0.07, 0.09))


func _cell(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	return Vector2.ZERO


func _cell_to_world(cell: Vector2) -> Vector2:
	return cell * CELL


func _visible_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2(-2000, -2000, 4000, 4000)
	var inv := vp.get_canvas_transform().affine_inverse()
	var size := vp.get_visible_rect().size
	var corners: Array[Vector2] = [inv * Vector2.ZERO, inv * Vector2(size.x, 0), inv * Vector2(0, size.y), inv * size]
	var tl := corners[0]
	var br := corners[0]
	for c in corners:
		tl = tl.min(c)
		br = br.max(c)
	return Rect2(tl, br - tl)
