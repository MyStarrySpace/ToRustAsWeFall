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
const RUNNING_COLOR := Color(1.0, 0.7, 0.3, 0.5)

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
	_mat.albedo_color = Color(color, 0.3)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
	_mat.albedo_color = RUNNING_COLOR if _running else Color(color, 0.3)

	# Collect the remaining waypoints first; only build a surface if there's a line to
	# draw (an empty ImmediateMesh surface logs a Godot error every idle frame).
	var points := _remaining_points()
	if points.size() < 2:
		_line.mesh = null
		return

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(1, points.size()):
		im.surface_add_vertex(points[i - 1])
		im.surface_add_vertex(points[i])
	im.surface_end()
	_line.mesh = im

## The not-yet-traversed leg as a polyline (start point + remaining waypoints), or
## fewer than 2 points when there's nothing to draw.
func _remaining_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if game_state != null and game_state.scheduler != null and char_id != "" and game_state.is_moving(char_id):
		var mv = game_state.characters[char_id].movement
		if mv:
			var path: Array[Vector3] = mv.path
			var cum_dist: Array[float] = mv.cum_dist
			var total: float = mv.total_distance
			var current_tick := game_state.scheduler.get_current_tick()
			var t := clampf((current_tick - mv.start_tick) / mv.duration, 0.0, 1.0) if mv.duration > 0 else 1.0
			var current_dist := t * total
			pts.append(_start_point())
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
