class_name CausalFeedbackLink
extends Node3D

## A reusable cause -> effect read for 3D gameplay objects.
##
## The link is deliberately cosmetic: hover, reveal-all, pause planning, and short
## wall-clock flashes only change presentation. Gameplay state never depends on it.
## Endpoints are sampled while visible, so switches can point at moving machinery,
## enemies, doors, or any future Node3D without bespoke update code.

const DEFAULT_DASH_COUNT := 8
const MODE_PREDICTED := "predicted"
const MODE_ACTIVE := "active"
const MODE_READY := "ready"
const MODE_WARNING := "warning"
const MODE_FAILED := "failed"
const MODE_COMPLETE := "complete"
const VALID_MODES := [MODE_PREDICTED, MODE_ACTIVE, MODE_READY, MODE_WARNING, MODE_FAILED, MODE_COMPLETE]
const VISIBILITY_CONTEXTUAL := "contextual"
const VISIBILITY_HOVER_ONLY := "hover_only"
const VALID_VISIBILITY_POLICIES := [VISIBILITY_CONTEXTUAL, VISIBILITY_HOVER_ONLY]
const CHARACTER_TINTS := {
	"aster": Color(0.29, 0.62, 1.0),
	"peris": Color(1.0, 0.67, 0.27),
	"endo": Color(0.4, 0.72, 0.55),
}

var source: Node3D = null
var target: Node3D = null
## Optional interaction delegate that requests this relationship on hover/click.
## The visible cause can then be a flora/enemy mesh while its larger Interactable
## remains the reliable input target.
var interaction_source: Node = null
var target_highlight: Node = null
var _target_highlight_reason := ""

var _tint := Color(1.0, 0.64, 0.2)
var _source_offset := Vector3(0.0, 0.65, 0.0)
var _target_offset := Vector3(0.0, 0.65, 0.0)
var _arc_height := 0.75
var _dash_count := DEFAULT_DASH_COUNT
var _label_text := "AFFECTS"
var _show_label := true
var _path_style := "dashes"
var _reverse_visual_direction := false
var _flow_speed := 0.0
var _feedback_mode := MODE_PREDICTED
var _visibility_policy := VISIBILITY_CONTEXTUAL
var _owner_character := ""
var _character_tint := Color(1.0, 0.64, 0.2)
var _draw_duration := 0.65
var _viewport_safe_margins := Vector4(36.0, 36.0, 36.0, 36.0)
var _reveal_started_msec := 0
var _arrival_burst_started_msec := 0
var _arrival_burst_until_msec := 0
var _arrival_strength := 1.0

var _source_hovered := false
var _highlighted := false
var _planning_active := false
var _latched := false
var _flash_until_msec := 0
var _flash_strength := 1.0
var _visibility_query := Callable()
var _perception_allowed := true
var _source_perceived := true
var _target_perceived := true

var _dashes: Array[MeshInstance3D] = []
var _source_ring: MeshInstance3D = null
var _target_ring: MeshInstance3D = null
var _arrival_ring: MeshInstance3D = null
var _packet: MeshInstance3D = null
var _label: Label3D = null
var _material: StandardMaterial3D = null
var _arrival_material: StandardMaterial3D = null
var _visuals_built := false
var _rendering_enabled := DisplayServer.get_name() != "headless"


func configure(source_node: Node3D, target_node: Node3D, tint: Color, opts: Dictionary = {}) -> void:
	source = source_node
	target = target_node
	interaction_source = opts.get("interaction_source", source_node) as Node
	_tint = tint
	target_highlight = opts.get("target_highlight", null) as Node
	_source_offset = opts.get("source_offset", _source_offset) as Vector3
	_target_offset = opts.get("target_offset", _target_offset) as Vector3
	_arc_height = maxf(0.0, float(opts.get("arc_height", _arc_height)))
	_dash_count = maxi(3, int(opts.get("dash_count", DEFAULT_DASH_COUNT)))
	_label_text = str(opts.get("label", _label_text))
	_show_label = bool(opts.get("show_label", true))
	_path_style = str(opts.get("path_style", "dashes"))
	_reverse_visual_direction = bool(opts.get("reverse_visual_direction", false))
	_flow_speed = maxf(0.0, float(opts.get("flow_speed", 0.0)))
	_owner_character = str(opts.get("owner_character", ""))
	var palette_tint: Color = CHARACTER_TINTS.get(_owner_character, tint)
	_character_tint = opts.get("character_tint", palette_tint) as Color
	var configured_visibility := str(opts.get("visibility_policy", VISIBILITY_CONTEXTUAL))
	_visibility_policy = configured_visibility if VALID_VISIBILITY_POLICIES.has(configured_visibility) \
		else VISIBILITY_CONTEXTUAL
	_draw_duration = maxf(0.0, float(opts.get("draw_duration", _draw_duration)))
	_viewport_safe_margins = opts.get("viewport_safe_margins", _viewport_safe_margins) as Vector4
	var configured_mode := str(opts.get("feedback_mode", MODE_PREDICTED))
	_feedback_mode = configured_mode if VALID_MODES.has(configured_mode) else MODE_PREDICTED
	_reveal_started_msec = Time.get_ticks_msec()
	var visibility_query_v: Variant = opts.get("visibility_query", Callable())
	if visibility_query_v is Callable:
		_visibility_query = visibility_query_v as Callable
	name = str(opts.get("name", "CausalFeedbackLink"))
	_target_highlight_reason = "causal_%d" % get_instance_id()
	# Keep authored/warped parents from bending the effect twice. The endpoints already
	# report their final world positions, and the link draws between those positions.
	set_meta("skip_coord_map_warp", true)
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build_visuals()
	_refresh_visibility()


func matches_source(candidate: Node) -> bool:
	return candidate != null and candidate == interaction_source


func get_target_node() -> Node3D:
	return target


## Bind to the same live character-perception roster that drives fog. The callable
## receives the final world-space cause/effect endpoints and returns whether both
## are currently perceived. No query keeps non-fog scenes backward-compatible.
func set_visibility_query(query: Callable) -> void:
	_visibility_query = query
	_refresh_visibility()


func set_source_hovered(active: bool) -> void:
	_source_hovered = active
	_refresh_visibility()


## Reveal-all (SHIFT) uses the same method as interactables and outline targets.
func set_highlight(active: bool) -> void:
	_highlighted = active
	_refresh_visibility()


## Planning pause is independent from SHIFT, so releasing either source cannot hide
## a link that is still requested by the other.
func set_planning_active(active: bool) -> void:
	_planning_active = active
	_refresh_visibility()


## Keep a relationship visible while its consequence is actively unfolding.
func set_latched(active: bool) -> void:
	_latched = active
	_refresh_visibility()


## State is part of the causal grammar, not gameplay. Hue stays owned by the
## character register; weight, continuity, cadence, packets, and endpoint motion
## distinguish what the relationship is doing without creating a second color code.
func set_feedback_mode(mode: String) -> void:
	if not VALID_MODES.has(mode) or mode == _feedback_mode:
		return
	_feedback_mode = mode
	_reveal_started_msec = Time.get_ticks_msec()
	if mode == MODE_READY:
		pulse_arrival(1.0, 0.85)
	elif mode == MODE_COMPLETE:
		pulse_arrival(1.35, 1.05)
	_refresh_visibility()


func get_feedback_mode() -> String:
	return _feedback_mode


## A world-space consequence beat at the visual destination. It remains cosmetic
## wall time so planning pause and deterministic fast-forward cannot change outcomes.
func pulse_arrival(strength := 1.0, duration := 0.9) -> void:
	var now_msec := Time.get_ticks_msec()
	var duration_msec := maxi(50, int(maxf(0.05, duration) * 1000.0))
	_arrival_burst_started_msec = now_msec
	_arrival_burst_until_msec = now_msec + duration_msec
	_arrival_strength = maxf(0.25, strength)
	_refresh_visibility()


## Relationship copy is state, too: a diverter can feed one branch while starving
## another. Let the owning system keep the displayed causal claim truthful as its
## topology changes without rebuilding the link (which would lose hover/pause wiring).
func set_relationship_label(text: String) -> void:
	_label_text = text
	if _label != null and is_instance_valid(_label):
		_label.text = text


func get_relationship_label() -> String:
	return _label_text


## Send a short, directional energy beat down the relationship line.
func flash(duration := 1.25, strength := 1.0) -> void:
	_flash_until_msec = maxi(_flash_until_msec, Time.get_ticks_msec() + int(maxf(0.05, duration) * 1000.0))
	_flash_strength = maxf(1.0, strength)
	_refresh_visibility()


func is_feedback_visible() -> bool:
	return visible


func get_feedback_state() -> Dictionary:
	return {
		"visible": visible,
		"requested": _feedback_requested(),
		"perception_allowed": _perception_allowed,
		"source_perceived": _source_perceived,
		"target_perceived": _target_perceived,
		"hovered": _source_hovered,
		"highlighted": _highlighted,
		"planning": _planning_active,
		"latched": _latched,
		"source_name": str(source.name) if is_instance_valid(source) else "",
		"interaction_source_name": str(interaction_source.name) if is_instance_valid(interaction_source) else "",
		"target_name": str(target.name) if is_instance_valid(target) else "",
		"label": _label_text,
		"show_label": _show_label,
		"path_style": _path_style,
		"reverse_visual_direction": _reverse_visual_direction,
		"flow_speed": _flow_speed,
		"feedback_mode": _feedback_mode,
		"visibility_policy": _visibility_policy,
		"owner_character": _owner_character,
		"mode_tint": _mode_tint(),
	}


func _feedback_requested() -> bool:
	if _visibility_policy == VISIBILITY_HOVER_ONLY:
		return _source_hovered
	return _source_hovered or _highlighted or _planning_active or _latched \
		or (_rendering_enabled and (Time.get_ticks_msec() < _flash_until_msec \
			or Time.get_ticks_msec() < _arrival_burst_until_msec))


func _is_perceived() -> bool:
	if _visibility_query.is_null() or not _visibility_query.is_valid():
		_source_perceived = true
		_target_perceived = true
		return true
	if not is_instance_valid(source) or not is_instance_valid(target):
		_source_perceived = false
		_target_perceived = false
		return false
	var start := source.global_position + _source_offset
	var finish := target.global_position + _target_offset
	_source_perceived = _segment_is_perceived(start, start)
	_target_perceived = _segment_is_perceived(finish, finish)
	return _source_perceived and _target_perceived


func _segment_is_perceived(from_world: Vector3, to_world: Vector3) -> bool:
	if _visibility_query.is_null() or not _visibility_query.is_valid():
		return true
	return bool(_visibility_query.call(from_world, to_world))


func _refresh_visibility() -> void:
	var was_visible := visible
	var requested := _feedback_requested() and is_instance_valid(source) and is_instance_valid(target)
	if requested:
		_perception_allowed = _is_perceived()
	else:
		_perception_allowed = false
		_source_perceived = false
		_target_perceived = false
	var perceived_request := requested and _perception_allowed
	visible = perceived_request
	if perceived_request and not was_visible:
		_reveal_started_msec = Time.get_ticks_msec()
	# Poll while requested even if currently unseen: when a scout enters sight the link
	# appears immediately without requiring pause/hover to be released and pressed again.
	set_process(requested and _rendering_enabled)
	if target_highlight != null and is_instance_valid(target_highlight):
		if target_highlight.has_method("set_external_highlight"):
			target_highlight.call("set_external_highlight", _target_highlight_reason, perceived_request)
		elif target_highlight.has_method("set_highlight"):
			target_highlight.call("set_highlight", perceived_request)
	if perceived_request and _rendering_enabled:
		_update_visuals(float(Time.get_ticks_msec()) * 0.001)


func _exit_tree() -> void:
	if target_highlight != null and is_instance_valid(target_highlight) \
			and target_highlight.has_method("set_external_highlight"):
		target_highlight.call("set_external_highlight", _target_highlight_reason, false)


func _process(_delta: float) -> void:
	# Rendering-only wall time keeps the packet/pulse alive during a gameplay planning
	# pause and rechecks the live party sight roster as characters move. It never feeds
	# the scheduler or any gameplay decision.
	_refresh_visibility()


func _build_visuals() -> void:
	if _visuals_built or not _rendering_enabled:
		return
	_visuals_built = true
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Additive, high-energy lines clipped to white on the compatibility renderer and
	# made short cause/effect reads look like shader artifacts. Preserve the owning
	# register's hue with a translucent mix plus restrained emission instead.
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_material.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.88)
	_material.emission_enabled = true
	_material.emission = _tint
	_material.emission_energy_multiplier = 1.8
	_material.no_depth_test = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Planning feedback must compose after the fragment perception stack (priority 126),
	# just like the outline mask. Otherwise valid world-space links disappear under fog.
	_material.render_priority = 127

	var dash_mesh: Mesh
	if _path_style == "movement_chevrons":
		dash_mesh = _make_chevron_mesh()
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 0.16, 1.0)
		dash_mesh = box
	for i in range(_dash_count):
		var dash := MeshInstance3D.new()
		dash.name = "Dash%02d" % i
		dash.mesh = dash_mesh
		dash.material_override = _material
		dash.set_meta("camera_occlusion_exempt", true)
		dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dash.layers = 2
		add_child(dash)
		dash.top_level = true
		_dashes.append(dash)

	_source_ring = _make_ring("CausePulse", 0.4, 0.52)
	_target_ring = _make_ring("EffectPulse", 0.58, 0.76)
	_arrival_ring = _make_ring("ArrivalRipple", 0.7, 0.84)
	_arrival_material = _material.duplicate() as StandardMaterial3D
	_arrival_ring.material_override = _arrival_material
	_arrival_ring.visible = false

	_packet = MeshInstance3D.new()
	_packet.name = "EffectPacket"
	var packet_mesh := SphereMesh.new()
	packet_mesh.radius = 0.24
	packet_mesh.height = 0.48
	_packet.mesh = packet_mesh
	_packet.material_override = _material
	_packet.set_meta("camera_occlusion_exempt", true)
	_packet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_packet.layers = 2
	add_child(_packet)
	_packet.top_level = true

	_label = Label3D.new()
	_label.name = "RelationshipLabel"
	_label.text = _label_text
	# Fixed-size text keeps the relationship readable at a planning-board camera height;
	# world-scaled Label3D text vanished precisely when the player most needed the overview.
	_label.font_size = 14
	_label.pixel_size = 0.007
	_label.fixed_size = true
	_label.modulate = Color(_tint.r, _tint.g, _tint.b, 0.96)
	_label.outline_modulate = Color(0.015, 0.02, 0.025, 0.9)
	_label.outline_size = 7
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.render_priority = 127
	add_child(_label)
	_label.top_level = true
	_label.visible = _show_label


## Flat luminous V-shaped arrowhead. Node3D.look_at points local -Z toward the
## next path sample, so the chevron tip is authored at negative Z.
func _make_chevron_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [
		Vector3(-0.42, 0.0, 0.34),
		Vector3(-0.15, 0.0, 0.34),
		Vector3(0.0, 0.0, -0.24),
		Vector3(0.0, 0.0, -0.52),
		Vector3(0.42, 0.0, 0.34),
		Vector3(0.15, 0.0, 0.34),
	]
	var triangles := [0, 1, 2, 0, 2, 3, 4, 2, 5, 4, 3, 2]
	for point_index in triangles:
		tool.set_normal(Vector3.UP)
		tool.add_vertex(points[point_index])
	return tool.commit()


func _make_ring(ring_name: String, inner_radius: float, outer_radius: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = ring_name
	var torus := TorusMesh.new()
	torus.inner_radius = inner_radius
	torus.outer_radius = outer_radius
	torus.rings = 20
	torus.ring_segments = 10
	ring.mesh = torus
	ring.material_override = _material
	ring.set_meta("camera_occlusion_exempt", true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.layers = 2
	add_child(ring)
	ring.top_level = true
	return ring


func _curve_point(t: float, start: Vector3, finish: Vector3) -> Vector3:
	var planar_distance := Vector2(start.x - finish.x, start.z - finish.z).length()
	var distance_bonus := minf(1.3, planar_distance * 0.035)
	# A nearby switch and target otherwise collapse to one unreadable blob in projection.
	# Give short relationships a pronounced question-mark arc instead of shortening the tell.
	var close_arc_bonus := maxf(0.0, 2.8 - planar_distance) * 0.42
	var control := (start + finish) * 0.5 + Vector3.UP * (_arc_height + distance_bonus + close_arc_bonus)
	var first := start.lerp(control, t)
	var second := control.lerp(finish, t)
	return first.lerp(second, t)


func _mode_tint() -> Color:
	return _character_tint


func _mode_flow_multiplier() -> float:
	match _feedback_mode:
		MODE_ACTIVE:
			return 1.45
		MODE_READY:
			return 0.72
		MODE_WARNING:
			return 2.0
		MODE_FAILED:
			return 0.0
		MODE_COMPLETE:
			return 0.9
		_:
			return 0.55


func _mode_weight_multiplier(pulse: float) -> float:
	match _feedback_mode:
		MODE_PREDICTED:
			return 0.78
		MODE_ACTIVE:
			return 1.05
		MODE_READY:
			return 1.18
		MODE_WARNING:
			return 0.88 + pulse * 0.46
		MODE_COMPLETE:
			return 1.25
		_:
			return 1.0


func _route_draw_progress(now_msec: int) -> float:
	# Warning/failure must never temporarily erase the route at the moment of urgency.
	if _feedback_mode in [MODE_READY, MODE_WARNING, MODE_FAILED, MODE_COMPLETE] or _draw_duration <= 0.0:
		return 1.0
	return clampf(float(now_msec - _reveal_started_msec) / (_draw_duration * 1000.0), 0.0, 1.0)


func _update_visuals(now: float) -> void:
	if not _visuals_built or not is_instance_valid(source) or not is_instance_valid(target):
		return
	var logical_start := source.global_position + _source_offset
	var logical_finish := target.global_position + _target_offset
	var start := logical_finish if _reverse_visual_direction else logical_start
	var finish := logical_start if _reverse_visual_direction else logical_finish
	# Planning pause may reveal every authored relationship at once. Only render a full
	# trail when both endpoints fit comfortably in the current view; this avoids giant
	# clipped labels/rings from later rooms while their logical feedback remains active.
	var camera := get_viewport().get_camera_3d()
	var in_frame := camera != null and not camera.is_position_behind(start) and not camera.is_position_behind(finish)
	if in_frame:
		var viewport_rect := get_viewport().get_visible_rect()
		var safe_rect := Rect2(
			viewport_rect.position + Vector2(_viewport_safe_margins.x, _viewport_safe_margins.y),
			viewport_rect.size - Vector2(
				_viewport_safe_margins.x + _viewport_safe_margins.z,
				_viewport_safe_margins.y + _viewport_safe_margins.w
			)
		)
		in_frame = safe_rect.has_point(camera.unproject_position(start)) \
			and safe_rect.has_point(camera.unproject_position(finish))
	_set_visual_parts_visible(in_frame)
	if not in_frame:
		return
	var now_msec := Time.get_ticks_msec()
	var pulse_speed := 11.0 if _feedback_mode == MODE_WARNING else (15.0 if _feedback_mode == MODE_FAILED else 7.0)
	var pulse := 0.5 + 0.5 * sin(now * pulse_speed)
	var flashing := now_msec < _flash_until_msec
	var energy := 1.05 + pulse * 0.32
	if _feedback_mode in [MODE_ACTIVE, MODE_READY]:
		energy += 0.5
	elif _feedback_mode in [MODE_WARNING, MODE_FAILED]:
		energy += 0.82
	if flashing:
		energy += 1.1 * _flash_strength
	var mode_tint := _mode_tint()
	_material.albedo_color = Color(mode_tint.r, mode_tint.g, mode_tint.b, 0.88)
	_material.emission = mode_tint
	_material.emission_energy_multiplier = energy

	var planar_distance := Vector2(start.x - finish.x, start.z - finish.z).length()
	# Nine full-width dashes across a two-metre relationship overlap into one bright
	# candy-cane blob. Short relationships need fewer marks, not smaller gaps.
	var active_dash_count := clampi(int(ceil(planar_distance / 0.8)), 3, _dashes.size())
	var dash_span := 0.58 / float(active_dash_count)
	var draw_progress := _route_draw_progress(now_msec)
	var flow_speed := _flow_speed * _mode_flow_multiplier()
	for i in range(_dashes.size()):
		var dash := _dashes[i]
		if i >= active_dash_count:
			dash.visible = false
			continue
		var sequence_t := (float(i) + 0.5) / float(active_dash_count)
		if sequence_t > draw_progress:
			dash.visible = false
			continue
		var center_t := sequence_t
		if _path_style == "movement_chevrons" and flow_speed > 0.0 and draw_progress >= 1.0:
			center_t = fposmod(center_t + now * flow_speed, 1.0)
		var a := _curve_point(maxf(0.0, center_t - dash_span * 0.5), start, finish)
		var b := _curve_point(minf(1.0, center_t + dash_span * 0.5), start, finish)
		if _feedback_mode == MODE_FAILED and i % 3 == 1:
			# A falsified relationship freezes into a visibly broken chain rather than
			# borrowing an unrelated warning hue.
			dash.visible = false
			continue
		dash.visible = _segment_is_perceived(a, b)
		var midpoint := (a + b) * 0.5
		if _feedback_mode == MODE_FAILED:
			midpoint += Vector3.UP * sin(now * 29.0 + float(i)) * 0.09
		dash.look_at_from_position(midpoint, b, Vector3.UP)
		if _path_style == "movement_chevrons":
			var base_scale := 0.88 + pulse * 0.14
			var weight := _mode_weight_multiplier(pulse)
			dash.scale = Vector3(base_scale * weight, base_scale, base_scale * weight)
		else:
			dash.scale = Vector3(1.0 + pulse * 0.16, 1.0 + pulse * 0.16, maxf(0.03, a.distance_to(b)))

	var packet_speed := (1.05 if flashing else 0.62) * maxf(0.22, _mode_flow_multiplier())
	var packet_t := fposmod(now * packet_speed, 1.0)
	_packet.global_position = _curve_point(packet_t, start, finish)
	_packet.visible = draw_progress >= 1.0 and _feedback_mode != MODE_FAILED \
		and _segment_is_perceived(_packet.global_position, _packet.global_position)
	_packet.scale = Vector3.ONE * (0.82 + pulse * (0.5 if flashing else 0.24))

	_source_ring.global_position = logical_start
	_target_ring.global_position = logical_finish
	_source_ring.visible = _segment_is_perceived(logical_start, logical_start)
	_target_ring.visible = _segment_is_perceived(logical_finish, logical_finish)
	_source_ring.rotation.y = now * 1.4
	_target_ring.rotation.y = -now * 1.8
	var anticipation_squeeze := 0.1 * sin(now * 13.0) if _feedback_mode == MODE_ACTIVE else 0.0
	var endpoint_scale := clampf(planar_distance / 3.5, 0.62, 1.0)
	_source_ring.scale = Vector3.ONE * endpoint_scale * (0.9 + pulse * 0.16 + anticipation_squeeze)
	_target_ring.scale = Vector3.ONE * endpoint_scale * (0.92 + pulse * (0.34 if flashing else 0.2))

	var arrival_active := now_msec < _arrival_burst_until_msec and _arrival_burst_until_msec > _arrival_burst_started_msec
	_arrival_ring.visible = arrival_active and _segment_is_perceived(finish, finish)
	if arrival_active:
		var burst_progress := clampf(float(now_msec - _arrival_burst_started_msec) \
			/ float(_arrival_burst_until_msec - _arrival_burst_started_msec), 0.0, 1.0)
		_arrival_ring.global_position = finish
		_arrival_ring.rotation.y = -now * 2.4
		_arrival_ring.scale = Vector3.ONE * lerpf(0.55, 2.5 * _arrival_strength, burst_progress)
		_arrival_material.albedo_color = Color(mode_tint.r, mode_tint.g, mode_tint.b, 1.0 - burst_progress)
		_arrival_material.emission = mode_tint
		_arrival_material.emission_energy_multiplier = lerpf(8.0 * _arrival_strength, 1.0, burst_progress)

	_label.global_position = _curve_point(0.5, start, finish) + Vector3.UP * 0.5
	_label.visible = _show_label and _segment_is_perceived(_label.global_position, _label.global_position)
	_label.modulate = Color(mode_tint.r, mode_tint.g, mode_tint.b, 0.82 + pulse * 0.18)


func _set_visual_parts_visible(active: bool) -> void:
	for dash in _dashes:
		dash.visible = active
	if _source_ring != null:
		_source_ring.visible = active
	if _target_ring != null:
		_target_ring.visible = active
	if _arrival_ring != null:
		_arrival_ring.visible = false
	if _packet != null:
		_packet.visible = active
	if _label != null:
		_label.visible = active and _show_label
