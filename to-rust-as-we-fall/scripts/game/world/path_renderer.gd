class_name PathRenderer
extends Node3D

## Reusable movement-path visual. Point it at a GameState character and it draws
## that character's remaining route as a translucent line, interpolated to the
## current scheduler tick. Any scene can show any character's path — player, party
## member, NPC, escort — by attaching one of these; the drawing lives here, not in
## each character controller.
##
## Two sources, checked in order:
##   1. GameState movement — the data-layer truth. Reads characters[id].movement and
##      draws the not-yet-traversed waypoints, so the line shrinks as the character
##      advances and (because position is a pure function of the scheduler tick) it
##      is fast-forward / replay invariant. This is the path for all real gameplay.
##   2. An explicit waypoint list — for movement that never touches GameState
##      (standalone / editor previews). Set via set_explicit_path().
##
## Purely cosmetic: it reads the scheduler clock but writes no game state, so it can
## live on _process and never affects determinism.

const HEIGHT_OFFSET := 0.08
const RUNNING_COLOR := Color(1.0, 0.7, 0.3, 0.7)
const WALK_ALPHA := 0.55
## The path draws as a flat ground RIBBON of this width (a 1px PRIMITIVE_LINES line was there
## before and was effectively invisible at gameplay-camera distance — the "no path in any scene").
const PATH_WIDTH := 0.24

## Data-layer character to visualize.
var game_state: GameState
var char_id := ""
## Base line tint (alpha is applied here). Running overrides it with RUNNING_COLOR.
var color := Color(1.0, 1.0, 1.0)
## Optional body to anchor the line's start to. When set, the line begins at this
## node's position (so it hugs the moving mesh exactly); otherwise it starts from
## the data-layer position of char_id.
var anchor: Node3D

var _running := false
var _explicit_path: Array[Vector3] = []
var _explicit_index := 0
var _line: MeshInstance3D
var _mat: StandardMaterial3D

func _ready() -> void:
	_line = MeshInstance3D.new()
	# top_level so the line is authored in world space (vertices are global), free of
	# the parent body's transform.
	_line.top_level = true
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(color, WALK_ALPHA)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # ribbon visible from either side
	_line.material_override = _mat
	add_child(_line)

## Bind to a data-layer character. anchor_node (optional) makes the line start track
## that node's position instead of the data-layer position.
func setup(state: GameState, id: String, line_color: Color, anchor_node: Node3D = null) -> void:
	game_state = state
	char_id = id
	color = line_color
	anchor = anchor_node

func set_running(running: bool) -> void:
	_running = running

## Draw an arbitrary path (movement not routed through GameState). Cleared by
## clear_explicit_path(). Ignored while the bound character is moving in GameState.
func set_explicit_path(path: Array[Vector3], from_index: int = 0) -> void:
	_explicit_path = path
	_explicit_index = from_index

func clear_explicit_path() -> void:
	_explicit_path = []
	_explicit_index = 0

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _line == null:
		return
	_mat.albedo_color = RUNNING_COLOR if _running else Color(color, WALK_ALPHA)

	# Collect the remaining waypoints first; only build a surface if there's a line to draw.
	var points := _remaining_points()
	if points.size() < 2:
		_line.mesh = null
		return
	_line.mesh = _build_ribbon(points)

## Build a flat ground-ribbon along the polyline (a quad per segment, PATH_WIDTH wide), so the
## path actually reads from the gameplay camera instead of a hairline. Cosmetic only.
func _build_ribbon(points: Array[Vector3]) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var half := PATH_WIDTH * 0.5
	for i in range(1, points.size()):
		var p0 := points[i - 1]
		var p1 := points[i]
		var flat := p1 - p0
		flat.y = 0.0
		if flat.length() < 0.0001:
			continue
		var dir := flat.normalized()
		var perp := Vector3(-dir.z, 0.0, dir.x) * half
		var a := p0 - perp
		var b := p0 + perp
		var c := p1 + perp
		var d := p1 - perp
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(d)
	return st.commit()

## The not-yet-traversed leg as a polyline (start point + remaining waypoints), or
## fewer than 2 points when there's nothing to draw.
func _remaining_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if game_state != null and game_state.scheduler != null and char_id != "" and game_state.is_moving(char_id):
		var mv = game_state.characters[char_id].movement
		if mv:
			var path: Array[Vector3] = mv.path
			var current_tick := game_state.scheduler.get_current_tick()
			pts.append(_start_point())
			# Draw every waypoint not yet reached. Use the real per-waypoint arrival_ticks (the
			# same source get_position interpolates from) — a linear distance estimate is wrong for
			# cooperative paths that wait at a cell, and would cull the wrong waypoints.
			var ticks = mv.get("arrival_ticks", [])
			if ticks is Array and (ticks as Array).size() == path.size():
				for i in range(path.size()):
					if float(ticks[i]) > current_tick:
						pts.append(path[i] + Vector3(0.0, HEIGHT_OFFSET, 0.0))
			else:
				var cum_dist: Array[float] = mv.cum_dist
				var total: float = mv.total_distance
				var t := clampf((current_tick - mv.start_tick) / mv.duration, 0.0, 1.0) if mv.duration > 0 else 1.0
				var current_dist := t * total
				for i in range(1, path.size()):
					if cum_dist[i] > current_dist:
						pts.append(path[i] + Vector3(0.0, HEIGHT_OFFSET, 0.0))
	elif _explicit_path.size() > 0:
		pts.append(_start_point())
		for i in range(_explicit_index, _explicit_path.size()):
			pts.append(_explicit_path[i] + Vector3(0.0, HEIGHT_OFFSET, 0.0))
	return pts

func _start_point() -> Vector3:
	if anchor != null:
		return anchor.global_position + Vector3(0.0, HEIGHT_OFFSET, 0.0)
	if game_state != null and char_id != "":
		return game_state.get_position(char_id) + Vector3(0.0, HEIGHT_OFFSET, 0.0)
	return global_position + Vector3(0.0, HEIGHT_OFFSET, 0.0)
