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

const HEIGHT_OFFSET := 0.06
const WARP_RESAMPLE := 0.6       # on a warped scene, resample the polyline to this flat spacing before warping
                                 # so the ribbon HUGS the curved deck instead of cutting a straight chord under it
const WARP_RESAMPLE_MAX_STEPS := 128  # cap per-segment subdivisions so a degenerate huge/non-finite segment
                                      # can't explode into millions of points (real segments are a few units)
const RUNNING_COLOR := Color(1.0, 0.7, 0.3, 0.85)
const WALK_ALPHA := 0.8
## The path draws as a flat ground RIBBON of this width (a 1px PRIMITIVE_LINES line was there
## before and was effectively invisible at gameplay-camera distance — the "no path in any scene").
const PATH_WIDTH := 0.34
const PREVIEW_WIDTH := 0.14     # the dim hover ribbon is a hint, not a hose
const DASH_LENGTH := 0.5
const DASH_GAP := 0.32

## Preview style: thinner and DASHED — the visual grammar for "not committed yet". A click commits
## and the solid ribbon takes over.
var preview_style := false

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
var _line: MeshInstance3D      # the live HEAD: one quad from the interpolated start to the first waypoint
var _tail: MeshInstance3D      # the static TAIL: the fixed remaining waypoints (rebuilt only on change)
var _mat: StandardMaterial3D
var _tail_cache: Array[Vector3] = []
var _points_cache: Array[Vector3] = []

func _ready() -> void:
	_line = MeshInstance3D.new()
	# top_level so the line is authored in world space (vertices are global), free of
	# the parent body's transform.
	_line.top_level = true
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(color, WALK_ALPHA)
	# OPAQUE, not alpha-blend: the preview scene doesn't composite the alpha-blend pass (opaque + Decals
	# draw, blended meshes don't), so a translucent ribbon was invisible — the "path never shows". A solid
	# unshaded ribbon reads clearly as a route on the floor.
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # ribbon visible from either side
	_line.material_override = _mat
	add_child(_line)
	_tail = MeshInstance3D.new()
	_tail.top_level = true
	_tail.material_override = _mat
	add_child(_tail)

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
		_tail.mesh = null
		_tail_cache = []
		_points_cache = []
		return
	# PREVIEW ribbons are static while hovering: rebuild only when the path itself changes.
	if preview_style:
		if points != _points_cache:
			_points_cache = points.duplicate()
			if GridWorld._pf_debug:
				GridWorld._pf_trace("[ribbon] preview rebuild %d pts (warped=%s)" % [points.size(), game_state != null and game_state.coord_map != null])
			_line.mesh = _build_ribbon(points)
			if GridWorld._pf_debug:
				GridWorld._pf_trace("[ribbon] preview built")
		_tail.mesh = null
		return
	# COMMITTED ribbons split: only the start point interpolates per tick, so the fixed remaining
	# waypoints (the TAIL — quads, corner discs, end cap) rebuild only when a waypoint is consumed;
	# the per-frame work is one HEAD quad from the live start to the first fixed waypoint.
	var tail := points.slice(1)
	if tail != _tail_cache:
		_tail_cache = tail.duplicate()
		_tail.mesh = _build_tail(tail)
	_line.mesh = _build_head(points[0], tail[0])

## The static remainder: segment quads between fixed waypoints, a disc at every waypoint (joint with
## the head at tail[0], rounded corners, rounded end).
func _build_tail(tail: Array[Vector3]) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var half := PATH_WIDTH * 0.5
	for i in range(1, tail.size()):
		_emit_quad(st, tail[i - 1], tail[i], half)
	for point in tail:
		_emit_disc(st, point, half)
	return st.commit()

func _build_head(start: Vector3, first: Vector3) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	_emit_quad(st, start, first, PATH_WIDTH * 0.5)
	return st.commit()

## Build a flat ground-ribbon along the polyline, so the path actually reads from the gameplay camera
## instead of a hairline. Committed paths are solid quads with a disc at every interior joint (no wedge
## gaps on turns — one connected line); the preview style is thinner and DASHED, walking the polyline by
## arc length so dashes flow continuously across corners. Cosmetic only.
func _build_ribbon(points: Array[Vector3]) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var half := (PREVIEW_WIDTH if preview_style else PATH_WIDTH) * 0.5
	if preview_style:
		_build_dashed(st, points, half)
	else:
		for i in range(1, points.size()):
			_emit_quad(st, points[i - 1], points[i], half)
		# Joint discs: cap every interior corner so consecutive quads read as ONE connected line.
		for i in range(1, points.size() - 1):
			_emit_disc(st, points[i], half)
	return st.commit()

func _emit_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, half: float) -> void:
	var flat := p1 - p0
	flat.y = 0.0
	if flat.length() < 0.0001:
		return
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

func _emit_disc(st: SurfaceTool, center: Vector3, radius: float) -> void:
	var sides := 8
	for s in range(sides):
		var a0 := TAU * float(s) / float(sides)
		var a1 := TAU * float(s + 1) / float(sides)
		st.add_vertex(center)
		st.add_vertex(center + Vector3(cos(a0), 0.0, sin(a0)) * radius)
		st.add_vertex(center + Vector3(cos(a1), 0.0, sin(a1)) * radius)

## Dashes by cumulative arc length over the whole polyline (corners don't reset the cycle).
const _MAX_DASHES := 6000   # crash-proof cap (a normal preview is ~100-500). A bogus far/huge start point
                            # would otherwise make seg_len enormous and spin this loop ~forever -> hang/OOM.

func _build_dashed(st: SurfaceTool, points: Array[Vector3], half: float) -> void:
	var cycle := DASH_LENGTH + DASH_GAP
	var travelled := 0.0
	var emitted := 0
	for i in range(1, points.size()):
		var p0 := points[i - 1]
		var p1 := points[i]
		# Skip any non-finite endpoint (a bad warp/position): emitting it would push NaN verts to the GPU.
		if not p0.is_finite() or not p1.is_finite():
			continue
		var flat := p1 - p0
		flat.y = 0.0
		var seg_len := flat.length()
		if seg_len < 0.0001:
			continue
		var dir := flat / seg_len
		var s := 0.0
		while s < seg_len and emitted < _MAX_DASHES:
			# Count EVERY iteration (emit OR gap). For a huge `travelled` (a bogus far segment), fmod loses
			# precision and `cycle - phase` can round to ~0, so the gap branch wouldn't advance `s` — an
			# infinite loop that an emit-only cap never breaks. maxf() guarantees forward progress; the cap
			# bounds the total.
			emitted += 1
			var phase := fmod(travelled + s, cycle)
			if phase < DASH_LENGTH:
				var run := minf(DASH_LENGTH - phase, seg_len - s)
				_emit_quad(st, p0 + dir * s, p0 + dir * (s + run), half)
				s += maxf(run, 0.0001)
			else:
				s += maxf(cycle - phase, 0.0001)
		travelled += seg_len
		if emitted >= _MAX_DASHES:
			break

## The not-yet-traversed leg as a polyline (start point + remaining waypoints), or
## fewer than 2 points when there's nothing to draw.
func _remaining_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var gy := _ground_y()
	if game_state != null and game_state.scheduler != null and char_id != "" and game_state.is_moving(char_id):
		var mv = game_state.characters[char_id].movement
		if mv:
			var path: Array[Vector3] = mv.path
			var current_tick := game_state.scheduler.get_current_tick()
			pts.append(_start_point(gy))
			# Draw every waypoint not yet reached. Use the real per-waypoint arrival_ticks (the
			# same source get_position interpolates from) — a linear distance estimate is wrong for
			# cooperative paths that wait at a cell, and would cull the wrong waypoints.
			var ticks = mv.get("arrival_ticks", [])
			if ticks is Array and (ticks as Array).size() == path.size():
				for i in range(path.size()):
					if float(ticks[i]) > current_tick:
						pts.append(Vector3(path[i].x, gy, path[i].z))
			else:
				var cum_dist: Array[float] = mv.cum_dist
				var total: float = mv.total_distance
				var t := clampf((current_tick - mv.start_tick) / mv.duration, 0.0, 1.0) if mv.duration > 0 else 1.0
				var current_dist := t * total
				for i in range(1, path.size()):
					if cum_dist[i] > current_dist:
						pts.append(Vector3(path[i].x, gy, path[i].z))
	elif _explicit_path.size() > 0:
		pts.append(_start_point(gy))
		for i in range(_explicit_index, _explicit_path.size()):
			pts.append(Vector3(_explicit_path[i].x, gy, _explicit_path[i].z))
	# On a warped scene (a coord_map maps the flat data onto a curved model, e.g. the channels helix),
	# map each flat waypoint onto the surface so the ribbon follows the deck, not the flat ground. RESAMPLE
	# the flat polyline first: a straight segment between two sparse waypoints warps to a CHORD that cuts
	# through the curving deck (the clip). Inserting intermediate flat points before warping makes the warped
	# ribbon hug the curve. (A single Decal can't span an arbitrary winding path — densifying the ribbon is
	# the conforming equivalent of the hover grid's project-down.)
	if game_state != null and game_state.coord_map != null:
		var warped: Array[Vector3] = []
		for i in range(pts.size()):
			if i > 0:
				var a := pts[i - 1]
				var b := pts[i]
				var steps := clampi(int(ceil(a.distance_to(b) / WARP_RESAMPLE)), 1, WARP_RESAMPLE_MAX_STEPS)
				for s in range(1, steps):
					warped.append(game_state.coord_map.to_world(a.lerp(b, float(s) / float(steps))))
			warped.append(game_state.coord_map.to_world(pts[i]))
		return warped
	return pts

## The ribbon hugs the FLOOR, not the character's waist. Movement waypoints carry the mover's body
## height (~0.5 for a gridless pos-move), which made the ribbon float; flatten every point to the
## floor under the character's level instead (grid level height when there's a grid, else y≈0).
func _ground_y() -> float:
	# Ride the grid's floor surface whenever there's a grid — INCLUDING preview ribbons (char_id == "").
	# Keying this on char_id buried the hover preview under a lifted modeled floor (origin.y > HEIGHT_OFFSET).
	if game_state != null and game_state.grid != null:
		var lvl := 0
		if char_id != "" and game_state.characters.has(char_id):
			lvl = game_state.get_character_level(char_id)
		return game_state.grid.origin.y + game_state.grid.level_height * float(lvl) + HEIGHT_OFFSET
	return HEIGHT_OFFSET

func _start_point(gy: float) -> Vector3:
	# On a warped scene _remaining_points warps the WHOLE polyline (incl. this start) through coord_map, so
	# the start MUST be a FLAT (data) position. The anchor's global_position is the ALREADY-WARPED node spot;
	# returning it would double-warp into a far, bogus point — the ribbon then starts off in space (drawn at
	# the wrong place / not visible, and a degenerate first segment). Prefer the flat data position; convert
	# a warped anchor/self back through to_data so every point in the polyline is in the same (flat) frame.
	var warped: bool = game_state != null and game_state.coord_map != null
	if game_state != null and char_id != "" and game_state.characters.has(char_id):
		var p := game_state.get_position(char_id)   # always flat data
		return Vector3(p.x, gy, p.z)
	if anchor != null:
		var ap := anchor.global_position
		if warped:
			ap = game_state.coord_map.to_data(ap)
		return Vector3(ap.x, gy, ap.z)
	var gp := global_position
	if warped:
		gp = game_state.coord_map.to_data(gp)
	return Vector3(gp.x, gy, gp.z)
