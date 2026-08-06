class_name PathRenderManager
extends Node3D

const ROUTE_PREVIEW_ANNOTATION_SCENE := preload(
	"res://scenes/ui/route_preview_annotation.tscn")

## Scene-level movement-path rendering. Add ONE of these per scene, point it at the GameState, and
## it draws a path ribbon for EVERY registered character that is moving (or has a queued move) —
## player, party member, NPC, escort — anchored to that character's node and tinted by it.
##
## This is the REUSABLE home for movement-path visuals. Do NOT bake a PathRenderer into one
## controller (it was in player.gd, so only the single player ever showed a path, and scenes that
## move other characters — the elevator party, escorts — showed nothing). The manager binds the
## GameState/char_id/anchor every frame from the SCENE's perspective, so a path appears regardless
## of whether the character's own node is processing, and a queued move (movement set while the
## scheduler is paused) draws too. Purely cosmetic — it reads the scheduler clock, writes nothing.

var game_state: GameState
var search_root: Node             # where character nodes live (defaults to the parent scene)
var default_color := Color(1.0, 0.7, 0.3)

var _renderers := {}              # char_id -> PathRenderer
var _dest_markers := {}           # char_id -> MeshInstance3D (the destination ring)
var _dest_ghosts := {}            # char_id -> Node3D (a translucent ghost of the character at its move target)
var _ghost_built_from := {}       # char_id -> Node3D the ghost was duplicated from (rebuild on node change)
var _ghost_colors := {}           # char_id -> last tint applied to the shared ghost material
var _nodes := {}                  # char_id -> Node3D (cached anchor; re-found if freed)
var _known_node_misses := {}      # char_id -> true; distinguishes throttled nulls from freed references
var _next_tree_scan_frame := 0    # one shared periodic/resolution scan gate for every actor
var _tracked_character_ids := {}  # char_id -> true; reconciles GameState unregisters with owned visuals
## Focused performance-test seam: number of actual shared search-root walks.
var _node_cache_scan_count := 0
var _path_feedback_source: Node   # optional chunk contract: get_paused_path_feedback(char_id)
var _feedback_roots := {}         # char_id -> Node3D containing cached risk ribbons + timing labels
var _feedback_hashes := {}        # char_id -> hash of the last returned feedback payload
var _route_preview_annotation_layer: CanvasLayer
var _route_preview_annotation: Label
var _route_preview_annotation_owner: Node

const GHOST_ALPHA := 0.45         # BG3-style faded destination preview (unshaded full-colour so it reads in the dark)
const FEEDBACK_WIDTH := 0.52       # sits around the ordinary route ribbon instead of hiding it
const FEEDBACK_LIFT := 0.10
const FEEDBACK_LABEL_LIFT := 0.82
const FEEDBACK_RESAMPLE := 0.5
const FEEDBACK_RESAMPLE_MAX_STEPS := 128
const NODE_RESCAN_INTERVAL_FRAMES := 30

func _ready() -> void:
	_ensure_route_preview_annotation()

func setup(state: GameState, root: Node = null) -> void:
	_ensure_route_preview_annotation()
	var next_root := root if root != null else get_parent()
	if game_state != state or search_root != next_root:
		_clear_managed_state()
		_path_feedback_source = null
	game_state = state
	search_root = next_root

## The cursor-adjacent route consequence is movement presentation, so it lives beside the shared
## ribbons and destination markers rather than below an arbitrary Player body. `owner` prevents an
## inactive sibling Player from clearing the active controller's cue during its own hover update.
func present_route_preview_annotation(owner: Node, screen_pos: Vector2, text: String) -> void:
	_ensure_route_preview_annotation()
	if owner == null or not is_instance_valid(owner) or text.is_empty() or text == "NO ROUTE":
		clear_route_preview_annotation(owner)
		return
	_route_preview_annotation_owner = owner
	_route_preview_annotation.text = text
	_route_preview_annotation.position = screen_pos + Vector2(18.0, 18.0)
	_route_preview_annotation.visible = true

func clear_route_preview_annotation(owner: Node = null) -> void:
	if owner != null and is_instance_valid(_route_preview_annotation_owner) \
			and _route_preview_annotation_owner != owner:
		return
	_route_preview_annotation_owner = null
	if _route_preview_annotation != null and is_instance_valid(_route_preview_annotation):
		_route_preview_annotation.text = ""
		_route_preview_annotation.visible = false

func get_route_preview_annotation_layer() -> CanvasLayer:
	_ensure_route_preview_annotation()
	return _route_preview_annotation_layer

func _ensure_route_preview_annotation() -> void:
	if _route_preview_annotation_layer != null \
			and is_instance_valid(_route_preview_annotation_layer):
		return
	_route_preview_annotation_layer = ROUTE_PREVIEW_ANNOTATION_SCENE.instantiate() as CanvasLayer
	add_child(_route_preview_annotation_layer)
	_route_preview_annotation = _route_preview_annotation_layer.get_node_or_null(
		"RoutePreviewAnnotation") as Label

## Bind the active chunk as an OPTIONAL, read-only path-feedback provider. A chunk that has no
## get_paused_path_feedback() method simply produces no overlays. Rebinding on a chunk reload clears
## the old cached meshes immediately so feedback can never leak between fragments.
func set_path_feedback_source(source: Node) -> void:
	if _path_feedback_source == source:
		return
	_path_feedback_source = source
	_clear_all_path_feedback()

func _process(_delta: float) -> void:
	if _route_preview_annotation_owner != null \
			and not is_instance_valid(_route_preview_annotation_owner):
		clear_route_preview_annotation()
	if Engine.is_editor_hint() or game_state == null:
		return
	var perf_started := PerformanceTrace.begin()
	_reconcile_character_registry()
	# One periodic shared refresh prevents a still-valid superseded node from becoming immortal when a
	# replacement with the same id enters before the old chunk is retired. It is ONE tree walk per interval,
	# independent of actor count; never-seen/stale ids may additionally request one immediate lifecycle scan.
	var cache_frame := Engine.get_process_frames()
	if not game_state.characters.is_empty() and cache_frame >= _next_tree_scan_frame:
		_refresh_node_cache(cache_frame)
	var planning := game_state.scheduler != null and game_state.scheduler.is_paused()
	var provider_ready := (
		planning
		and _path_feedback_source != null
		and is_instance_valid(_path_feedback_source)
		and _path_feedback_source.has_method("get_paused_path_feedback")
	)
	if not provider_ready:
		if _feedback_roots.size() > 0:
			_clear_all_path_feedback()
		if _path_feedback_source != null and not is_instance_valid(_path_feedback_source):
			_path_feedback_source = null
	# Iterating the Dictionary directly avoids allocating a fresh keys Array on
	# every frame. More importantly, resolve an actor's opt-out before allocating
	# its renderer/materials; ambient NPCs and enemies normally never need them.
	for char_id in game_state.characters:
		_tracked_character_ids[str(char_id)] = true
		var actor_started := PerformanceTrace.begin()
		var feedback: Array = []
		if provider_ready:
			var provider_started := PerformanceTrace.begin()
			var provided = _path_feedback_source.call("get_paused_path_feedback", str(char_id))
			if provided is Array:
				feedback = provided
			PerformanceTrace.end(&"update", &"path_manager.feedback_query", provider_started, str(char_id), feedback.size())
		var resolve_started := PerformanceTrace.begin()
		var pr: PathRenderer = _renderers.get(char_id)
		var node := _node_for(char_id)
		PerformanceTrace.end(&"update", &"path_manager.resolve_actor", resolve_started, str(char_id), 1 if node != null else 0)
		# A node can opt OUT of the ribbon (NPC ambience walks default off; an escort opts back in).
		# Learned hazard feedback is the one planning-only exception: a normally hidden enemy route is
		# relevant when it actually crosses the learned surge, so reveal that route while this overlay exists.
		var opted_out: bool = node != null and "show_movement_path" in node and not node.show_movement_path
		var suppressed: bool = opted_out and feedback.is_empty()
		if suppressed:
			if pr != null and is_instance_valid(pr):
				pr.visible = false
				_renderers.erase(char_id)
				if pr.get_parent() == self:
					remove_child(pr)
				pr.queue_free()
			_hide_destination_visuals(char_id)
			_clear_char_path_feedback(char_id)
			PerformanceTrace.end(&"draw", &"path_manager.actor", actor_started, str(char_id), 0)
			continue
		var bind_started := PerformanceTrace.begin()
		if pr == null or not is_instance_valid(pr):
			pr = PathRenderer.new()
			add_child(pr)
			_renderers[char_id] = pr
		pr.visible = true
		var actor_color := _color_for(node)
		# Bind on creation and when the anchor node changes (late creation / chunk reloads), not
		# every frame — the per-frame full re-setup was redundant field churn. Tint is a cheap
		# field update of its own so a runtime faction/status colour change still propagates.
		if pr.game_state != game_state or pr.char_id != char_id or pr.anchor != node:
			pr.setup(game_state, char_id, actor_color, node)
		elif pr.color != actor_color:
			pr.color = actor_color
		pr.set_running(game_state.is_running(char_id))
		PerformanceTrace.end(&"draw", &"path_manager.bind_renderer", bind_started, str(char_id), 1)
		var marker_started := PerformanceTrace.begin()
		_update_dest_marker(char_id, node)
		PerformanceTrace.end(&"draw", &"path_manager.destination_marker", marker_started, str(char_id), 1)
		var ghost_started := PerformanceTrace.begin()
		_update_dest_ghost(char_id, node)
		PerformanceTrace.end(&"draw", &"path_manager.destination_ghost", ghost_started, str(char_id), 1)
		var feedback_started := PerformanceTrace.begin()
		_update_path_feedback(char_id, feedback)
		PerformanceTrace.end(&"draw", &"path_manager.feedback_draw", feedback_started, str(char_id), feedback.size())
		PerformanceTrace.end(&"draw", &"path_manager.actor", actor_started, str(char_id), 1)
	PerformanceTrace.end(&"draw", &"path_manager.process", perf_started, "characters", game_state.characters.size())

## GameState is a RefCounted data model, so scene nodes cannot rely on tree-exit alone to learn that an
## id was unregistered. Reconcile the small set of ids this manager has actually seen, and synchronously
## retire every owned visual before dropping its cache entries. This runs before rendering so a removed
## character cannot leave a destination ring/ghost visible for one extra frame.
func _reconcile_character_registry() -> void:
	for raw_id in _tracked_character_ids.keys():
		var char_id := str(raw_id)
		if not game_state.characters.has(char_id):
			_remove_character_state(char_id)
	for raw_id in game_state.characters:
		_tracked_character_ids[str(raw_id)] = true

func _remove_character_state(char_id: String) -> void:
	_retire_owned_visual(_renderers.get(char_id))
	_retire_owned_visual(_dest_markers.get(char_id))
	_retire_owned_visual(_dest_ghosts.get(char_id))
	_clear_char_path_feedback(char_id)
	_renderers.erase(char_id)
	_dest_markers.erase(char_id)
	_dest_ghosts.erase(char_id)
	_ghost_built_from.erase(char_id)
	_ghost_colors.erase(char_id)
	_nodes.erase(char_id)
	_known_node_misses.erase(char_id)
	_feedback_roots.erase(char_id)
	_feedback_hashes.erase(char_id)
	_tracked_character_ids.erase(char_id)

func _retire_owned_visual(candidate: Variant) -> void:
	if candidate == null or not is_instance_valid(candidate) or not candidate is Node:
		return
	var visual := candidate as Node
	if visual is Node3D:
		(visual as Node3D).visible = false
	if visual.get_parent() == self:
		remove_child(visual)
	visual.queue_free()

## setup() is allowed to rebind this reusable manager to another GameState/root. A valid Node reference
## from the previous scene is still valid to Godot, so merely clearing freed entries is insufficient:
## retire all old visuals and reset the entire ownership/cache generation at the rebind boundary.
func _clear_managed_state() -> void:
	clear_route_preview_annotation()
	var ids := {}
	for raw_id in _renderers:
		ids[str(raw_id)] = true
	for raw_id in _dest_markers:
		ids[str(raw_id)] = true
	for raw_id in _dest_ghosts:
		ids[str(raw_id)] = true
	for raw_id in _ghost_built_from:
		ids[str(raw_id)] = true
	for raw_id in _ghost_colors:
		ids[str(raw_id)] = true
	for raw_id in _nodes:
		ids[str(raw_id)] = true
	for raw_id in _known_node_misses:
		ids[str(raw_id)] = true
	for raw_id in _feedback_roots:
		ids[str(raw_id)] = true
	for raw_id in _feedback_hashes:
		ids[str(raw_id)] = true
	for raw_id in _tracked_character_ids:
		ids[str(raw_id)] = true
	for raw_id in ids:
		_remove_character_state(str(raw_id))
	_renderers.clear()
	_dest_markers.clear()
	_dest_ghosts.clear()
	_ghost_built_from.clear()
	_ghost_colors.clear()
	_nodes.clear()
	_known_node_misses.clear()
	_feedback_roots.clear()
	_feedback_hashes.clear()
	_tracked_character_ids.clear()
	_next_tree_scan_frame = 0
	_node_cache_scan_count = 0

## Learned surge timing is presented as a wider colour-coded ribbon only while planning. The chunk
## supplies flat DATA-space points and copy; this manager owns all rendering/warping so the mechanic
## remains cosmetic and works on both flat scenes and coord-mapped decks.
func _update_path_feedback(char_id: String, feedback: Array) -> void:
	if feedback.is_empty():
		_clear_char_path_feedback(char_id)
		return
	var signature := hash(feedback)
	var cached: Node3D = _feedback_roots.get(char_id)
	if cached != null and is_instance_valid(cached) and _feedback_hashes.get(char_id) == signature:
		return
	_clear_char_path_feedback(char_id)
	var root := Node3D.new()
	root.name = "PathFeedback_%s" % char_id
	add_child(root)
	for raw_span in feedback:
		if raw_span is Dictionary:
			_build_path_feedback_span(root, char_id, raw_span)
	if root.get_child_count() == 0:
		root.queue_free()
		return
	_feedback_roots[char_id] = root
	_feedback_hashes[char_id] = signature

func _build_path_feedback_span(root: Node3D, char_id: String, span: Dictionary) -> void:
	var points := _feedback_data_points(span.get("points", []), char_id)
	if points.size() < 2:
		return
	var risk := str(span.get("risk", "safe"))
	var col := _path_feedback_color(risk)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := false
	for i in range(1, points.size()):
		var data_a: Vector3 = points[i - 1]
		var data_b: Vector3 = points[i]
		var a := _feedback_world_point(data_a)
		var b := _feedback_world_point(data_b)
		if not a.is_finite() or not b.is_finite():
			continue
		var tangent := b - a
		if tangent.length_squared() < 0.000001:
			continue
		tangent = tangent.normalized()
		var up := _feedback_up(data_a.lerp(data_b, 0.5))
		var side := up.cross(tangent)
		if side.length_squared() < 0.000001:
			side = Vector3.UP.cross(tangent)
		if side.length_squared() < 0.000001:
			continue
		side = side.normalized() * FEEDBACK_WIDTH * 0.5
		var a0 := a - side
		var a1 := a + side
		var b0 := b - side
		var b1 := b + side
		st.set_normal(up)
		st.add_vertex(a0)
		st.add_vertex(a1)
		st.add_vertex(b1)
		st.add_vertex(a0)
		st.add_vertex(b1)
		st.add_vertex(b0)
		emitted = true
	if not emitted:
		return
	var mesh := st.commit()
	if mesh == null:
		return
	var ribbon := MeshInstance3D.new()
	ribbon.name = "Risk_%s" % str(span.get("id", risk))
	ribbon.mesh = mesh
	ribbon.material_override = _make_path_feedback_material(col)
	ribbon.top_level = true
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ribbon.layers = 2
	root.add_child(ribbon)

	var copy := str(span.get("label", ""))
	if copy.is_empty():
		return
	var label := Label3D.new()
	label.name = "Timing_%s" % str(span.get("id", risk))
	label.text = copy
	label.font_size = 12
	label.pixel_size = 0.006
	label.fixed_size = true
	label.modulate = col
	label.outline_size = 8
	label.outline_modulate = Color(0.02, 0.025, 0.035, 0.96)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 127
	label.top_level = true
	root.add_child(label)
	var mid_data: Vector3 = points[int(points.size() / 2)]
	var label_pos := _feedback_world_point(mid_data)
	label.global_position = label_pos + _feedback_up(mid_data) * FEEDBACK_LABEL_LIFT

func _feedback_data_points(raw_points: Variant, char_id: String) -> Array[Vector3]:
	var source: Array[Vector3] = []
	if not raw_points is Array:
		return source
	var raw_array: Array = raw_points
	var ground_y := _feedback_ground_y(char_id)
	for raw in raw_array:
		if raw is Vector3:
			var p: Vector3 = raw
			if p.is_finite():
				source.append(Vector3(p.x, ground_y, p.z))
	if source.size() < 2:
		return source
	var dense: Array[Vector3] = [source[0]]
	for i in range(1, source.size()):
		var a := source[i - 1]
		var b := source[i]
		var flat_distance := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		var steps := clampi(int(ceil(flat_distance / FEEDBACK_RESAMPLE)), 1, FEEDBACK_RESAMPLE_MAX_STEPS)
		for s in range(1, steps + 1):
			dense.append(a.lerp(b, float(s) / float(steps)))
	return dense

func _feedback_ground_y(char_id: String) -> float:
	if game_state != null and game_state.grid != null:
		var level := game_state.get_character_level(char_id) if game_state.characters.has(char_id) else 0
		return game_state.grid.origin.y + game_state.grid.level_height * float(level) + PathRenderer.HEIGHT_OFFSET
	return PathRenderer.HEIGHT_OFFSET

func _feedback_world_point(data_point: Vector3) -> Vector3:
	var world := data_point
	if game_state != null and game_state.coord_map != null:
		world = game_state.coord_map.to_world(data_point)
	return world + _feedback_up(data_point) * FEEDBACK_LIFT

func _feedback_up(data_point: Vector3) -> Vector3:
	if game_state != null and game_state.coord_map != null and game_state.coord_map.has_method("to_basis"):
		var mapped = game_state.coord_map.to_basis(data_point)
		if mapped is Basis:
			var mapped_basis: Basis = mapped
			var mapped_up := mapped_basis.y
			if mapped_up.length_squared() > 0.000001:
				return mapped_up.normalized()
	return Vector3.UP

func _path_feedback_color(risk: String) -> Color:
	match risk:
		"danger":
			return Color(1.0, 0.18, 0.13)
		"close":
			return Color(1.0, 0.62, 0.08)
		_:
			return Color(0.18, 0.94, 0.42)

func _make_path_feedback_material(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 127
	return mat

func _hide_destination_visuals(char_id: String) -> void:
	var marker: MeshInstance3D = _dest_markers.get(char_id)
	if marker != null and is_instance_valid(marker):
		marker.visible = false
	var ghost: Node3D = _dest_ghosts.get(char_id)
	if ghost != null and is_instance_valid(ghost):
		ghost.visible = false

func _clear_char_path_feedback(char_id: String) -> void:
	var root: Node3D = _feedback_roots.get(char_id)
	if root != null and is_instance_valid(root):
		root.visible = false
		if root.get_parent() == self:
			remove_child(root)
		root.queue_free()
	_feedback_roots.erase(char_id)
	_feedback_hashes.erase(char_id)

func _clear_all_path_feedback() -> void:
	for char_id in _feedback_roots.keys().duplicate():
		_clear_char_path_feedback(str(char_id))

## A per-character DESTINATION ring at the end of its current move — the marker the player used to carry
## alone, now drawn for EVERY character in that character's colour. It reads the DATA-LAYER move target
## (get_destination), or the controller's exact formation preview before release, so a movable held rally
## shows every final slot as well as every route. Cosmetic: reads move/preview targets, writes nothing.
func _update_dest_marker(char_id: String, node: Node3D) -> void:
	var marker: MeshInstance3D = _dest_markers.get(char_id)
	var dest_data := Vector3.INF
	# An active preview is the prospective plan and must outrank the character's current
	# committed destination; otherwise rerallying a moving unit leaves its ring behind.
	if node != null and "preview_move_target" in node:
		var preview = node.preview_move_target
		if preview is Vector3 and (preview as Vector3).is_finite():
			dest_data = preview
	if not dest_data.is_finite():
		dest_data = game_state.get_destination(char_id)
	if not dest_data.is_finite():
		if marker != null:
			marker.visible = false
		return
	if marker == null:
		marker = _make_dest_marker(_color_for(node))
		add_child(marker)
		_dest_markers[char_id] = marker
	# Re-tint if the anchor's colour resolved late (lazy node find).
	(marker.material_override as StandardMaterial3D).albedo_color = Color(_color_for(node), 0.0)
	var dest_world: Vector3 = dest_data if game_state.coord_map == null else game_state.coord_map.to_world(dest_data)
	if not dest_world.is_finite():
		marker.visible = false
		return
	marker.visible = true
	marker.global_position = Vector3(dest_world.x, dest_world.y + 0.06, dest_world.z)
	var pulse: float = 0.3 + sin(Time.get_ticks_msec() * 0.004) * 0.15  # @rendering_only — destination ring pulse
	(marker.material_override as StandardMaterial3D).albedo_color.a = pulse
	# On flat scenes shrink the ring as the character closes on the target; the helix dest sits on a curved
	# deck so leave it full-size there.
	if game_state.coord_map == null:
		var cur: Vector3 = game_state.get_render_position(char_id)
		var dist: float = Vector2(cur.x - dest_world.x, cur.z - dest_world.z).length()
		var s: float = clampf(dist / 3.0, 0.3, 1.2)
		marker.scale = Vector3(s, s, s)
	else:
		marker.scale = Vector3.ONE

func _make_dest_marker(col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.3
	torus.rings = 16
	torus.ring_segments = 8
	m.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Draw after the perception-overlay quad (render_priority 126) so the ring survives the data-view (a
	# transparent surface is otherwise excluded from the overlay's screen texture and vanishes under it).
	mat.render_priority = 127
	# No depth test: like the ghost + ribbon, the destination ring reads through a wall / faded overhead deck.
	mat.no_depth_test = true
	m.material_override = mat
	m.rotation.x = -PI / 2.0
	m.top_level = true   # authored in world space — we set the global position to the move target
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # a UI overlay, not a caster
	m.layers = 2   # NO_GRID_DECAL_LAYER (player.gd): the hover grid skips the ring too
	return m

## A BG3-style DESTINATION GHOST: a faded, character-tinted copy of the character's mesh standing at its move
## target — so the player reads where each queued/moving character is HEADED before (and while) it walks there.
## Reads the data-layer move target (get_destination) so a party/escort member moved by a group command shows a
## ghost too. Cosmetic: duplicates meshes + reads the move target / coord_map, writes nothing.
func _update_dest_ghost(char_id: String, node: Node3D) -> void:
	var ghost: Node3D = _dest_ghosts.get(char_id)
	var ghost_color := _color_for(node)
	var dest_data := Vector3.INF
	# The active preview is the prospective plan, so it outranks an existing committed destination.
	# This keeps a moving party's ghosts attached to the rally formation currently being placed.
	if node != null and "preview_move_target" in node:
		var pv = node.preview_move_target
		if pv is Vector3 and (pv as Vector3).is_finite():
			dest_data = pv
	if not dest_data.is_finite():
		dest_data = game_state.get_destination(char_id)
	if not dest_data.is_finite() or node == null:
		if ghost != null and is_instance_valid(ghost):
			ghost.visible = false
		return
	# (Re)build when missing or the source node changed (late spawn / chunk reload): the ghost mirrors whatever
	# meshes the character actually has, so it stays correct as character visuals evolve.
	if ghost == null or not is_instance_valid(ghost) or _ghost_built_from.get(char_id) != node:
		if ghost != null and is_instance_valid(ghost):
			# queue_free() is DEFERRED — a top_level ghost stays valid, visible, and drawn by the
			# RenderingServer at its old world position until end-of-frame. Since the new ghost is built and
			# shown THIS same _process call, that left two ghosts on screen for the frame (the "ghost at
			# multiple positions" bug). Hide + detach synchronously first so only one ever draws.
			ghost.visible = false
			remove_child(ghost)
			ghost.queue_free()
		ghost = _build_dest_ghost(node, ghost_color)
		_dest_ghosts[char_id] = ghost
		_ghost_built_from[char_id] = node
		if ghost == null:
			_ghost_colors.erase(char_id)
			return
		_ghost_colors[char_id] = ghost_color
	elif _ghost_colors.get(char_id) != ghost_color:
		_retint_dest_ghost(ghost, ghost_color)
		_ghost_colors[char_id] = ghost_color
	var dest_world: Vector3 = dest_data if game_state.coord_map == null else game_state.coord_map.to_world(dest_data)
	if not dest_world.is_finite():
		ghost.visible = false
		return
	# Orient to the destination's deck basis on a warped scene (the helix deck tilts), upright otherwise.
	var basis := Basis()
	if game_state.coord_map != null and game_state.coord_map.has_method("to_basis"):
		var b = game_state.coord_map.to_basis(dest_data)
		if b is Basis:
			basis = b
	# Match the character's WORLD scale: the ghost meshes are captured as char-LOCAL transforms (node_inv strips
	# the character's scale), and the ghost root is top_level (no inherited parent scale), so without re-applying
	# the scale the ghost rendered at 1x — half-size in a scene whose root is scaled 2x (aster sim). get_scale()
	# folds the character's world scale back in so the ghost matches the body the player sees, at any scene scale.
	var char_scale: Vector3 = node.global_transform.basis.get_scale()
	ghost.global_transform = Transform3D(basis.scaled(char_scale), dest_world)
	ghost.visible = true

func _retint_dest_ghost(ghost: Node3D, col: Color) -> void:
	if ghost == null or not is_instance_valid(ghost):
		return
	for child in ghost.get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color = Color(col.r, col.g, col.b, GHOST_ALPHA)

## Duplicate every MeshInstance3D under the character into a top-level ghost root, sharing one translucent
## tinted material. Returns null when the character has no meshes yet (rebuilt next frame). The mesh transforms
## are captured RELATIVE to the character node, so the ghost reproduces the character's silhouette + feet offset.
func _build_dest_ghost(node: Node3D, col: Color) -> Node3D:
	if node == null or not is_instance_valid(node):
		return null
	var sources: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		sources.append(node)
	var ghost := Node3D.new()
	ghost.name = "DestGhost_%s" % str(node.name)
	ghost.top_level = true   # placed in world space at the move target
	add_child(ghost)
	var mat := _make_ghost_material(col)
	var node_inv := node.global_transform.affine_inverse()
	var built := false
	for s in sources:
		var mi := s as MeshInstance3D
		# The ghost is the character's BODY silhouette ONLY. Skip top_level meshes: the active player's own
		# path-preview ribbon and the party-preview renderers (PathRenderer, top_level so their vertices are
		# world-space) are CHILDREN of the player node, so find_children swept them in — duplicating ribbon
		# geometry into the ghost stamped a giant garbled green slab at the move target (it spanned to the
		# hovered cell, so it grew/shrank with the hover). A body mesh follows the character (never top_level).
		if mi == null or mi.mesh == null or mi.top_level or _is_under_path_renderer(mi):
			continue
		var g := MeshInstance3D.new()
		g.mesh = mi.mesh
		g.transform = node_inv * mi.global_transform
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.layers = 2   # NO_GRID_DECAL_LAYER: the hover grid skips the ghost too
		ghost.add_child(g)
		built = true
	if not built:
		ghost.queue_free()
		return null
	return ghost

## True if `node` sits under a PathRenderer (the route/preview ribbon). Those meshes are attached to the
## character but are NOT body geometry, so the destination ghost must never duplicate them.
func _is_under_path_renderer(node: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p is PathRenderer:
			return true
		p = p.get_parent()
	return false

func _make_ghost_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, GHOST_ALPHA)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Draw after the perception-overlay quad (render_priority 126) so the ghost stays visible in data-view too
	# (transparent surfaces are excluded from the screen texture the overlay rewrites from).
	m.render_priority = 127
	# No depth test: a wall or the helix coil overhead between camera and target would otherwise depth-hide the
	# destination ghost, so it vanished behind faded geometry. The ghost is a UI preview of where the character is
	# headed — it should always read, like the route ribbon.
	m.no_depth_test = true
	return m

func _color_for(node: Node) -> Color:
	if node != null and "color" in node:
		return node.color
	return default_color

func _node_for(char_id: String) -> Node3D:
	var had_entry := _nodes.has(char_id)
	var cached = _nodes.get(char_id)
	if _is_cached_node_current(char_id, cached):
		return cached as Node3D
	# A non-null entry that stopped satisfying the cache contract (renamed, reparented,
	# queued/freed, or replaced during a chunk swap) is a lifecycle event, not an ordinary
	# miss: refresh immediately so its replacement can bind in this frame. Keep explicit
	# miss state because Godot may collapse a freed Object Variant to null after deletion.
	var known_miss := had_entry and _known_node_misses.has(char_id)
	var stale_entry := had_entry and not known_miss
	if had_entry:
		_nodes[char_id] = null
	# Resolve every never-seen actor with ONE shared tree walk. _refresh_node_cache marks
	# every currently registered id as known (including null misses), so the first new id
	# finds all of its siblings and the rest remain behind the shared throttle.
	var frame := Engine.get_process_frames()
	if had_entry and not stale_entry and frame < _next_tree_scan_frame:
		return null
	_refresh_node_cache(frame)
	var refreshed = _nodes.get(char_id)
	return refreshed as Node3D if _is_cached_node_current(char_id, refreshed) else null

func _is_cached_node_current(char_id: String, candidate: Variant) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not candidate is Node3D:
		return false
	var node := candidate as Node3D
	if node.is_queued_for_deletion() or not node.is_inside_tree():
		return false
	if search_root == null or not is_instance_valid(search_root) or search_root.is_queued_for_deletion():
		return false
	if node != search_root and not search_root.is_ancestor_of(node):
		return false
	# Both manager-owned and character-owned PathRenderers expose char_id. They are
	# visual consumers of the anchor, never actor anchors themselves.
	if node is PathRenderer or node == self or is_ancestor_of(node):
		return false
	if not "char_id" in node or str(node.char_id) != char_id:
		return false
	return true

func _refresh_node_cache(frame: int) -> void:
	var perf_started := PerformanceTrace.begin()
	_next_tree_scan_frame = frame + NODE_RESCAN_INTERVAL_FRAMES
	if (game_state == null or search_root == null or not is_instance_valid(search_root)
		or search_root.is_queued_for_deletion() or not search_root.is_inside_tree()):
		PerformanceTrace.end(&"update", &"path_manager.node_cache_scan", perf_started, "no_root", 0)
		return
	for raw_id in _nodes.keys():
		if not game_state.characters.has(str(raw_id)):
			_nodes.erase(raw_id)
	for raw_id in _known_node_misses.keys():
		if not game_state.characters.has(str(raw_id)):
			_known_node_misses.erase(raw_id)
	for char_id in game_state.characters:
		var normalized_id := str(char_id)
		_nodes[normalized_id] = null
		_known_node_misses[normalized_id] = true
		_tracked_character_ids[normalized_id] = true
	_node_cache_scan_count += 1
	var descendants := search_root.find_children("*", "", true, false)
	for n in descendants:
		# Skip the manager's OWN subtree: PathRenderers (which also carry a char_id) and the dest markers/ghosts
		# live under here, so a naive char_id match would return a ribbon renderer instead of the character node.
		if n == self or is_ancestor_of(n):
			continue
		if n is Node3D and "char_id" in n:
			var found_id := str(n.char_id)
			if game_state.characters.has(found_id) and _is_cached_node_current(found_id, n):
				_nodes[found_id] = n
				_known_node_misses.erase(found_id)
	PerformanceTrace.end(&"update", &"path_manager.node_cache_scan", perf_started,
		"shared", descendants.size())
