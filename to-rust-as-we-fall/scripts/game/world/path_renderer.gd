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
## PATH_WIDTH was authored against the ~10 m Aster-sim camera. The elevator's
## camera is less than half that distance, where the same world width becomes a
## screen-filling hose. Scale the cosmetic ribbon with camera distance so its
## apparent width and dash cadence stay consistent between fragments.
const REFERENCE_CAMERA_DISTANCE := 10.0
const MIN_PROJECTED_WIDTH_SCALE := 0.38
const MAX_PROJECTED_WIDTH_SCALE := 1.5
const PATH_GHOST_SHADER := preload("res://resources/path_ghost.gdshader")

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
var _head_mesh := ImmediateMesh.new()
var _tail_cache: Array[Vector3] = []
var _points_cache: Array[Vector3] = []
var _head_points_buffer: Array[Vector3] = []
var _projected_width_scale := 1.0
var _explicit_revision := 0
var _rendered_explicit_revision := -1
var _cached_explicit_start := Vector3.INF
var _cached_coord_map_token := -1
var _movement_token := -1
var _movement_index := -1
var _movement_ground_y := INF
var _last_movement_tick := -INF
var _tail_first_data := Vector3.INF
var _cached_head_start_data := Vector3.INF
var _cached_head_end_data := Vector3.INF
var _last_material_tint := Color(-1.0, -1.0, -1.0, -1.0)

## Read-only counters for focused performance regressions. These count expensive
## static mesh builds, not frames; an unchanged route leaves both unchanged.
var _tail_rebuild_count := 0
var _preview_rebuild_count := 0
var _head_update_count := 0

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
	# Full-screen perception materials stop at priority 126. Routes are planning
	# feedback, so draw in the reserved final slot like destination rings/ghosts;
	# otherwise Aster's data view repaints the solid ground ribbon and leaves only
	# the sparse through-wall checker pass visible.
	_mat.render_priority = 127
	# THE THROUGH-WALL CONTRACT (the shifting-decal report): the SOLID ribbon depth-tests. It used
	# to draw with no_depth_test so the route survived the helix deck / faded walls — but painted
	# at floor depth onto a BUILDING FACE near the camera (the dressed districts put whole facades
	# in the foreground), the route parallax-slides across that face as the camera moves: an "odd
	# decal". The behind-geometry read now lives in the NEXT-PASS GHOST below: it draws through
	# occluders, but as a dim world-anchored checker that samples scene depth and discards itself
	# wherever the solid ribbon is already visible.
	_mat.no_depth_test = false
	_mat.next_pass = _make_ghost_pass()
	_line.material_override = _mat
	add_child(_line)
	_tail = MeshInstance3D.new()
	_tail.top_level = true
	_tail.material_override = _mat
	add_child(_tail)

## Bind to a data-layer character. anchor_node (optional) makes the line start track
## that node's position instead of the data-layer position.
func setup(state: GameState, id: String, line_color: Color, anchor_node: Node3D = null) -> void:
	var source_changed := game_state != state or char_id != id or anchor != anchor_node
	game_state = state
	char_id = id
	color = line_color
	anchor = anchor_node
	if source_changed:
		_invalidate_source_caches()

func set_running(running: bool) -> void:
	_running = running

## Draw an arbitrary path (movement not routed through GameState). Cleared by
## clear_explicit_path(). Ignored while the bound character is moving in GameState.
func set_explicit_path(path: Array[Vector3], from_index: int = 0) -> void:
	var next_index := clampi(from_index, 0, path.size())
	if _explicit_path == path and _explicit_index == next_index:
		return
	_explicit_path = path.duplicate()
	_explicit_index = next_index
	_explicit_revision += 1
	if GridWorld._fx_debug:
		GridWorld._pf_trace("[ribbon preview=%s] set_explicit_path %d pts from=%d: %s" % [preview_style, path.size(), from_index, str(path)])

func clear_explicit_path() -> void:
	if _explicit_path.is_empty() and _explicit_index == 0:
		return
	_explicit_path = []
	_explicit_index = 0
	_explicit_revision += 1

## Depth-aware checker fallback: visible only where opaque geometry covers the solid route.
func _make_ghost_pass() -> ShaderMaterial:
	var ghost := ShaderMaterial.new()
	ghost.shader = PATH_GHOST_SHADER
	ghost.render_priority = 127
	ghost.set_shader_parameter("tint", Color(color, 1.0).darkened(0.25))
	return ghost

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _line == null:
		return
	var perf_started := PerformanceTrace.begin()
	# Top-level meshes do not reliably inherit visibility on Web, so mirror it.
	var render_visible := is_visible_in_tree()
	_line.visible = render_visible
	_tail.visible = render_visible
	if not render_visible:
		PerformanceTrace.end(&"draw", &"path_renderer.process", perf_started, char_id, 0)
		return
	_update_material_tint()

	if _has_committed_movement():
		_process_committed_path()
	elif not _explicit_path.is_empty():
		_process_explicit_path()
	else:
		_clear_drawables()
		_reset_movement_cache()
	PerformanceTrace.end(&"draw", &"path_renderer.process", perf_started, char_id, _points_cache.size() + _tail_cache.size())

func _update_material_tint() -> void:
	var tint := RUNNING_COLOR if _running else Color(color, WALK_ALPHA)
	if tint == _last_material_tint:
		return
	_last_material_tint = tint
	_mat.albedo_color = tint
	var ghost := _mat.next_pass as ShaderMaterial
	if ghost != null:
		ghost.set_shader_parameter(
			"tint",
			(RUNNING_COLOR if _running else Color(color, 1.0)).darkened(0.25)
		)

func _has_committed_movement() -> bool:
	return (
		game_state != null
		and game_state.scheduler != null
		and char_id != ""
		and game_state.characters.has(char_id)
		and game_state.is_moving(char_id)
		# Mechanism-owned external traversals do not carry an ordinary waypoint route.
		and game_state.characters[char_id].get("movement") is Dictionary
	)

## The expensive part of a committed route is invariant between waypoint arrivals:
## all fixed waypoints, warp resampling, and the tail mesh. Cache that by scheduler
## handle + next-waypoint index. Only the short character-to-next-waypoint head is
## updated every frame, into one reusable ImmediateMesh resource.
func _process_committed_path() -> void:
	var perf_started := PerformanceTrace.begin()
	var mv: Dictionary = game_state.characters[char_id].movement
	var path: Array[Vector3] = mv.get("path", [])
	var current_tick := float(game_state.scheduler.get_current_tick())
	var token := _movement_identity(mv)
	var next_index := _remaining_waypoint_index(mv, current_tick, token)
	if next_index < 0 or next_index >= path.size():
		_clear_drawables()
		_reset_movement_cache()
		PerformanceTrace.end(&"draw", &"path_renderer.committed", perf_started, char_id, 0)
		return

	var gy := _ground_y()
	var start_data := _start_point(gy)
	var start_world := _map_data_point(start_data)
	if not start_world.is_finite():
		_clear_drawables()
		PerformanceTrace.end(&"draw", &"path_renderer.committed", perf_started, "invalid_start", 0)
		return
	var width_scale := _width_scale_for_world_point(start_world)
	var coord_token := _coord_map_token()
	var static_dirty := (
		token != _movement_token
		or next_index != _movement_index
		or not is_equal_approx(gy, _movement_ground_y)
		or coord_token != _cached_coord_map_token
		or not is_equal_approx(width_scale, _projected_width_scale)
	)
	if static_dirty:
		_projected_width_scale = width_scale
		var fixed_data: Array[Vector3] = []
		for i in range(next_index, path.size()):
			fixed_data.append(Vector3(path[i].x, gy, path[i].z))
		var fixed_world := _world_polyline(fixed_data)
		var joint_world := _map_data_points(fixed_data)
		_tail_cache = fixed_world.duplicate()
		_tail.mesh = _build_tail_cached(fixed_world, joint_world) if not fixed_world.is_empty() else null
		_tail_first_data = fixed_data[0] if not fixed_data.is_empty() else Vector3.INF
		_movement_token = token
		_movement_index = next_index
		_movement_ground_y = gy
		_cached_coord_map_token = coord_token
		_tail_rebuild_count += 1

	if not _tail_first_data.is_finite():
		_clear_drawables()
		PerformanceTrace.end(&"draw", &"path_renderer.committed", perf_started, "invalid_tail", 0)
		return
	var head_dirty := (
		static_dirty
		or not start_data.is_equal_approx(_cached_head_start_data)
		or not _tail_first_data.is_equal_approx(_cached_head_end_data)
	)
	if head_dirty:
		_fill_world_segment(_head_points_buffer, start_data, _tail_first_data)
		_update_head_mesh(_head_points_buffer)
		_cached_head_start_data = start_data
		_cached_head_end_data = _tail_first_data
	_last_movement_tick = current_tick
	PerformanceTrace.end(&"draw", &"path_renderer.committed", perf_started, char_id, path.size() - next_index)

## Explicit hover/rally paths only change on a new resolved destination. Rebuild
## their full dashed mesh when that revision, anchor, warp, or quantized width
## changes; stationary frames do no route allocation or coordinate-map work.
func _process_explicit_path() -> void:
	var perf_started := PerformanceTrace.begin()
	_reset_movement_cache()
	var gy := _ground_y()
	var start_data := _start_point(gy)
	var start_world := _map_data_point(start_data)
	if not start_world.is_finite():
		_clear_drawables()
		PerformanceTrace.end(&"draw", &"path_renderer.explicit", perf_started, "invalid_start", 0)
		return
	var width_scale := _width_scale_for_world_point(start_world)
	var coord_token := _coord_map_token()
	var dirty := (
		_explicit_revision != _rendered_explicit_revision
		or not start_data.is_equal_approx(_cached_explicit_start)
		or coord_token != _cached_coord_map_token
		or not is_equal_approx(width_scale, _projected_width_scale)
	)
	if not dirty:
		PerformanceTrace.end(&"draw", &"path_renderer.explicit", perf_started, "cached", _points_cache.size())
		return
	_projected_width_scale = width_scale
	_cached_explicit_start = start_data
	_cached_coord_map_token = coord_token
	_rendered_explicit_revision = _explicit_revision
	var data_points: Array[Vector3] = [start_data]
	for i in range(_explicit_index, _explicit_path.size()):
		data_points.append(Vector3(_explicit_path[i].x, gy, _explicit_path[i].z))
	var points := _world_polyline(data_points)
	_points_cache = points.duplicate()
	_tail.mesh = null
	if points.size() < 2:
		if GridWorld._fx_debug and preview_style:
			GridWorld._pf_trace("[ribbon] preview NO-DRAW: %d source points" % data_points.size())
		_line.mesh = null
		PerformanceTrace.end(&"draw", &"path_renderer.explicit", perf_started, "too_short", points.size())
		return
	if GridWorld._fx_debug and preview_style:
		GridWorld._pf_trace("[ribbon] preview REBUILD %d pts (warped=%s)" % [
			points.size(), game_state != null and game_state.coord_map != null])
	_line.mesh = _build_ribbon(points)
	_preview_rebuild_count += 1
	PerformanceTrace.end(&"draw", &"path_renderer.explicit", perf_started, "rebuilt", points.size())

func _movement_identity(mv: Dictionary) -> int:
	# Scheduler handles are monotonic and every movement replacement receives a
	# new one. Include route shape as a fallback for hand-authored movement data.
	var handle := int(mv.get("handle", -1))
	if handle >= 0:
		return handle
	var path: Array = mv.get("path", [])
	return hash([mv.get("start_tick", 0.0), path.size(), path[-1] if not path.is_empty() else Vector3.ZERO])

func _remaining_waypoint_index(mv: Dictionary, current_tick: float, token: int) -> int:
	var path: Array = mv.get("path", [])
	if path.is_empty():
		return -1
	var i := _movement_index if token == _movement_token else 0
	if current_tick < _last_movement_tick:
		i = 0
	var ticks = mv.get("arrival_ticks", [])
	if ticks is Array and (ticks as Array).size() == path.size():
		while i < path.size() and float(ticks[i]) <= current_tick:
			i += 1
		return i
	var cum_dist: Array = mv.get("cum_dist", [])
	var duration := float(mv.get("duration", 0.0))
	var total := float(mv.get("total_distance", 0.0))
	var t := clampf((current_tick - float(mv.get("start_tick", current_tick))) / duration, 0.0, 1.0) \
		if duration > 0.0 else 1.0
	var current_dist := t * total
	i = maxi(i, 1)
	while i < path.size() and i < cum_dist.size() and float(cum_dist[i]) <= current_dist:
		i += 1
	return i

func _coord_map_token() -> int:
	if game_state == null or game_state.coord_map == null:
		return 0
	if game_state.coord_map is Object:
		return (game_state.coord_map as Object).get_instance_id()
	return hash(game_state.coord_map)

func _map_data_point(point: Vector3) -> Vector3:
	if game_state != null and game_state.coord_map != null:
		return game_state.coord_map.to_world(point)
	return point

func _map_data_points(data_points: Array[Vector3]) -> Array[Vector3]:
	var world_points: Array[Vector3] = []
	for point in data_points:
		world_points.append(_map_data_point(point))
	return world_points

func _world_polyline(data_points: Array[Vector3]) -> Array[Vector3]:
	var perf_started := PerformanceTrace.begin()
	if game_state == null or game_state.coord_map == null:
		var flat := data_points.duplicate()
		PerformanceTrace.end(&"draw", &"path_renderer.world_polyline", perf_started, "flat", flat.size())
		return flat
	var world_points: Array[Vector3] = []
	for i in range(data_points.size()):
		if i > 0:
			var a := data_points[i - 1]
			var b := data_points[i]
			var steps := clampi(int(ceil(a.distance_to(b) / WARP_RESAMPLE)), 1, WARP_RESAMPLE_MAX_STEPS)
			for s in range(1, steps):
				world_points.append(game_state.coord_map.to_world(a.lerp(b, float(s) / float(steps))))
		world_points.append(game_state.coord_map.to_world(data_points[i]))
	PerformanceTrace.end(&"draw", &"path_renderer.world_polyline", perf_started, "warped", world_points.size())
	return world_points

func _fill_world_segment(out: Array[Vector3], a: Vector3, b: Vector3) -> void:
	out.clear()
	if game_state == null or game_state.coord_map == null:
		out.append(a)
		out.append(b)
		return
	var steps := clampi(int(ceil(a.distance_to(b) / WARP_RESAMPLE)), 1, WARP_RESAMPLE_MAX_STEPS)
	for s in range(steps + 1):
		out.append(game_state.coord_map.to_world(a.lerp(b, float(s) / float(steps))))

func _update_head_mesh(points: Array[Vector3]) -> void:
	var perf_started := PerformanceTrace.begin()
	_head_mesh.clear_surfaces()
	var drawable := false
	for i in range(1, points.size()):
		var flat := points[i] - points[i - 1]
		flat.y = 0.0
		if points[i - 1].is_finite() and points[i].is_finite() and flat.length_squared() >= 0.00000001:
			drawable = true
			break
	if not drawable:
		_line.mesh = null
		PerformanceTrace.end(&"draw", &"path_renderer.head_mesh", perf_started, "empty", points.size())
		return
	_head_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := PATH_WIDTH * _projected_width_scale * 0.5
	for i in range(1, points.size()):
		_emit_quad_immediate(_head_mesh, points[i - 1], points[i], half)
	_head_mesh.surface_end()
	_line.mesh = _head_mesh
	_head_update_count += 1
	PerformanceTrace.end(&"draw", &"path_renderer.head_mesh", perf_started, "rebuilt", points.size())

func _emit_quad_immediate(mesh: ImmediateMesh, p0: Vector3, p1: Vector3, half: float) -> void:
	if not p0.is_finite() or not p1.is_finite():
		return
	var flat := p1 - p0
	flat.y = 0.0
	if flat.length_squared() < 0.00000001:
		return
	var dir := flat.normalized()
	var perp := Vector3(-dir.z, 0.0, dir.x) * half
	var vertices := [p0 - perp, p0 + perp, p1 + perp, p0 - perp, p1 + perp, p1 - perp]
	for vertex in vertices:
		mesh.surface_set_normal(Vector3.UP)
		mesh.surface_add_vertex(vertex)

func _clear_drawables() -> void:
	if _head_mesh.get_surface_count() > 0:
		_head_mesh.clear_surfaces()
	_line.mesh = null
	_tail.mesh = null
	_tail_cache.clear()
	_points_cache.clear()
	_tail_first_data = Vector3.INF

func _reset_movement_cache() -> void:
	_movement_token = -1
	_movement_index = -1
	_movement_ground_y = INF
	_last_movement_tick = -INF
	_tail_first_data = Vector3.INF
	_cached_head_start_data = Vector3.INF
	_cached_head_end_data = Vector3.INF

func _invalidate_source_caches() -> void:
	_reset_movement_cache()
	_rendered_explicit_revision = -1
	_cached_explicit_start = Vector3.INF
	_cached_coord_map_token = -1
	_points_cache.clear()
	_tail_cache.clear()

func _build_tail_cached(tail: Array[Vector3], joint_points: Array[Vector3]) -> Mesh:
	var perf_started := PerformanceTrace.begin()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var half := PATH_WIDTH * _projected_width_scale * 0.5
	for i in range(1, tail.size()):
		_emit_quad(st, tail[i - 1], tail[i], half)
	# Warped routes need dense segment quads to hug the deck, but only authored
	# waypoints need round joins. Discs at every resample multiplied vertices ~5x.
	var caps := joint_points if not joint_points.is_empty() else tail
	for point in caps:
		_emit_disc(st, point, half)
	var mesh := st.commit()
	PerformanceTrace.end(&"draw", &"path_renderer.tail_mesh", perf_started, "rebuilt", tail.size())
	return mesh

## Build a flat ground-ribbon along the polyline, so the path actually reads from the gameplay camera
## instead of a hairline. Committed paths are solid quads with a disc at every interior joint (no wedge
## gaps on turns — one connected line); the preview style is thinner and DASHED, walking the polyline by
## arc length so dashes flow continuously across corners. Cosmetic only.
func _build_ribbon(points: Array[Vector3]) -> Mesh:
	var perf_started := PerformanceTrace.begin()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var half := (PREVIEW_WIDTH if preview_style else PATH_WIDTH) * _projected_width_scale * 0.5
	if preview_style:
		_build_dashed(st, points, half)
	else:
		for i in range(1, points.size()):
			_emit_quad(st, points[i - 1], points[i], half)
		# Joint discs: cap every interior corner so consecutive quads read as ONE connected line.
		for i in range(1, points.size() - 1):
			_emit_disc(st, points[i], half)
	var mesh := st.commit()
	PerformanceTrace.end(&"draw", &"path_renderer.ribbon_mesh", perf_started, "preview" if preview_style else "solid", points.size())
	return mesh

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
	var dash_length := DASH_LENGTH * _projected_width_scale
	var dash_gap := DASH_GAP * _projected_width_scale
	var cycle := dash_length + dash_gap
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
			if phase < dash_length:
				var run := minf(dash_length - phase, seg_len - s)
				_emit_quad(st, p0 + dir * s, p0 + dir * (s + run), half)
				s += maxf(run, 0.0001)
			else:
				s += maxf(cycle - phase, 0.0001)
		travelled += seg_len
		if emitted >= _MAX_DASHES:
			break

func _width_scale_for_camera_distance(camera_distance: float) -> float:
	return clampf(
		camera_distance / REFERENCE_CAMERA_DISTANCE,
		MIN_PROJECTED_WIDTH_SCALE,
		MAX_PROJECTED_WIDTH_SCALE
	)

func _width_scale_for_world_point(world_point: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 1.0
	# Quantization avoids rebuilding static route meshes for imperceptible follow-
	# camera interpolation while still responding promptly to player zoom.
	var raw_scale := _width_scale_for_camera_distance(camera.global_position.distance_to(world_point))
	return snappedf(raw_scale, 0.025)

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
	return _world_polyline(pts)

## The ribbon hugs the FLOOR, not the character's waist. Movement waypoints carry the mover's body
## height (~0.5 for a gridless pos-move), which made the ribbon float; flatten every point to the
## floor under the character's level instead (grid level height when there's a grid, else y≈0).
func _ground_y() -> float:
	# Ride the grid's floor surface whenever there's a grid — INCLUDING preview ribbons (char_id == "").
	# Keying this on char_id buried the hover preview under a lifted modeled floor (origin.y > HEIGHT_OFFSET).
	# A preview deliberately has no movement char_id, but it is anchored to the character whose route it
	# previews. In a stacked scene (the elevator), inherit that anchor's level; defaulting every preview to
	# level 0 put the upper-deck route four metres below the cabin floor.
	if game_state != null and game_state.grid != null:
		var lvl := 0
		var ground_char_id := char_id
		if ground_char_id == "" and anchor != null and "char_id" in anchor:
			ground_char_id = str(anchor.get("char_id"))
		if ground_char_id != "" and game_state.characters.has(ground_char_id):
			lvl = game_state.get_character_level(ground_char_id)
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
