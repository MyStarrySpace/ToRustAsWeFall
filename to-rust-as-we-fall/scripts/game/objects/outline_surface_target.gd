@tool
class_name OutlineSurfaceTarget
extends StaticBody3D

## Pickable room object with object-local outline and selected feedback.

@export var hover_enabled := true
@export var hover_outline_color := Color.WHITE
@export var selected_feedback_color := Color(1.0, 0.62, 0.12, 1.0)
@export var object_outline_enabled := true
# Outline widths are now SCREEN-SPACE (fraction of viewport height), constant at any distance — see the shader.
@export var hover_object_outline_width := 0.012
@export var selected_object_outline_width := 0.02
@export var selected_object_glow_strength := 3.8
@export var outline_highlight_radius := 0.0
@export var outline_highlight_extents := Vector3.ZERO
@export var outline_highlight_height := 0.8
@export var selected_feedback_duration := 3.0
@export var selected_particle_count := 180
@export var selected_particles_enabled := true
@export var outline_particles_enabled := true
@export var outline_particles_per_mesh := 220
@export var debug_particle_anchor_enabled := true
@export_node_path("Node") var interaction_delegate_path: NodePath

var _interaction_delegate: Node
var _selected_particles: GPUParticles3D
var _selected_particle_material: ParticleProcessMaterial
var _debug_anchor: MeshInstance3D
var _highlight_meshes: Array[MeshInstance3D] = []
var _original_overlays := {}
var _outline_particles := {}
var _hovered := false
var _selected := false
var _feedback_managed := false
var _selection_token := 0
# The crisp outline is now a SCREEN-SPACE mask (OutlineMaskManager) — clean on flat-shaded meshes, constant width
# at any distance. _outline_active is the logical "outline showing" flag (what has_active_mesh_outline reports);
# the manager does the actual rendering. Null manager (headless test / standalone) => flag only, no render.
var _outline_active := false
var _glow_active := false      # the QUEUED energy glow (set on begin_queued_feedback); has_active_glow() reports it
var _active_outline_color := Color.WHITE
var _mask_manager: OutlineMaskManager = null
var _highlight_requested := false
var _external_highlight_reasons := {}
var _interaction_pulse: MeshInstance3D = null
var _interaction_pulse_material: StandardMaterial3D = null
var _interaction_pulse_tween: Tween = null

signal outline_hovered(interactable: Node)
signal outline_unhovered(interactable: Node)
signal outline_selected(interactable: Node)
signal interaction_requested(interactable: Node, world_position: Vector3)

func _ready() -> void:
	if interaction_delegate_path != NodePath(""):
		_interaction_delegate = get_node_or_null(interaction_delegate_path)
	collision_layer = 4 if hover_enabled else 0
	collision_mask = 0
	input_ray_pickable = hover_enabled
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)

func _on_mouse_entered() -> void:
	if GridWorld._fx_debug:
		GridWorld._pf_trace("[outline] HIT surface-target '%s' (hover_enabled=%s managed=%s layer=%d pickable=%s)" % [
			name, hover_enabled, _feedback_managed, collision_layer, input_ray_pickable])
	if not hover_enabled:
		return
	if not _feedback_managed:
		set_hover_feedback(true)
	outline_hovered.emit(self)

func _on_mouse_exited() -> void:
	if not _feedback_managed:
		set_hover_feedback(false)
	outline_unhovered.emit(self)

func _on_input_event(_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if not hover_enabled:
		return
	if event is InputEventMouseButton:
		# The `command` action (right mouse) is the interact command (mirror of Interactable). A `select`
		# (left) click over the mesh is NEVER an interaction — it falls through to a plain move/select.
		if event.is_action_pressed("command"):
			var viewport := get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
			interaction_requested.emit(self, event_position)
			outline_selected.emit(self)

func set_interaction_delegate(delegate: Node) -> void:
	_interaction_delegate = delegate

func get_interaction_delegate() -> Node:
	return _valid_interaction_delegate()

func play_selected_feedback(origin: Vector3 = Vector3.ZERO, use_world_origin := false) -> void:
	# Legacy burst API: the queued energy glow replaced the particle sprays entirely.
	return
	_ensure_selected_particles()
	_selected_particles.amount = maxi(1, selected_particle_count)
	_selected_particles.lifetime = maxf(0.1, selected_feedback_duration)
	_selected_particle_material.color = selected_feedback_color
	_set_particle_draw_color(_selected_particles, selected_feedback_color, 8.0)
	var feedback_origin := origin if use_world_origin else _get_feedback_origin()
	_selected_particles.global_position = feedback_origin
	_show_debug_anchor(feedback_origin)
	_restart_particle_emitter(_selected_particles)

func _ensure_selected_particles() -> void:
	if _selected_particles != null:
		return
	_selected_particles = GPUParticles3D.new()
	_selected_particles.name = "SelectedParticles"
	_selected_particles.amount = maxi(1, selected_particle_count)
	_selected_particles.lifetime = maxf(0.1, selected_feedback_duration)
	_selected_particles.one_shot = false
	_selected_particles.explosiveness = 0.0
	_selected_particles.emitting = false
	_selected_particles.visible = false
	_selected_particles.top_level = true
	_selected_particles.local_coords = false
	_selected_particles.visibility_aabb = AABB(Vector3(-6.0, -6.0, -6.0), Vector3(12.0, 12.0, 12.0))

	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.09
	particle_mesh.height = 0.18
	particle_mesh.material = _make_particle_draw_material(selected_feedback_color, 8.0)
	_selected_particles.draw_pass_1 = particle_mesh

	_selected_particle_material = ParticleProcessMaterial.new()
	_selected_particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_selected_particle_material.emission_sphere_radius = maxf(0.35, get_outline_highlight_radius() * 0.2)
	_selected_particle_material.direction = Vector3.UP
	_selected_particle_material.spread = 180.0
	_selected_particle_material.initial_velocity_min = 0.02
	_selected_particle_material.initial_velocity_max = 0.12
	_selected_particle_material.gravity = Vector3.ZERO
	_selected_particle_material.scale_min = 0.12
	_selected_particle_material.scale_max = 0.26
	_selected_particle_material.color = selected_feedback_color
	_selected_particles.process_material = _selected_particle_material
	add_child(_selected_particles)

func set_feedback_managed(active: bool) -> void:
	_feedback_managed = active

func is_feedback_managed() -> bool:
	return _feedback_managed

func set_hover_feedback(active: bool) -> void:
	if GridWorld._fx_debug:
		GridWorld._pf_trace("[outline] '%s'.set_hover_feedback(%s) -> set_highlight" % [name, active])
	_hovered = active
	set_highlight(active)
	# Hovering the OBJECT is hovering the INTERACTABLE: forward to the delegate (same as clicks), so
	# its hover semantics — the // NAME // readout above all — fire no matter which surface the
	# cursor found. (The delegate drives set_highlight on this target, never back into this method,
	# so there is no ping-pong.)
	var delegate := _valid_interaction_delegate()
	if delegate != null and delegate.has_method("set_hover_feedback"):
		delegate.call("set_hover_feedback", active)

## Highlight = the crisp outline hull ONLY. Used by BOTH hover and the hold-SHIFT reveal so they
## read identically. The energy GLOW is reserved for a QUEUED interaction (click-committed, en
## route) — it never shows on mere hover. While a queue is active the stronger feedback stays.
func set_highlight(active: bool) -> void:
	_highlight_requested = active
	_refresh_highlight_request()


## Independent systems (causal links, accessibility reads, tutorials) can request the
## same outline without clearing hover/SHIFT or each other. `reason` is stable per owner.
func set_external_highlight(reason: String, active: bool) -> void:
	if active:
		_external_highlight_reasons[reason] = true
	else:
		_external_highlight_reasons.erase(reason)
	_refresh_highlight_request()


func _refresh_highlight_request() -> void:
	var active := _highlight_requested or not _external_highlight_reasons.is_empty()
	if GridWorld._fx_debug:
		GridWorld._pf_trace("[outline] target '%s'.set_highlight(%s) selected=%s highlight_meshes=%d enabled=%s" % [
			name, active, _selected, _highlight_meshes.size(), object_outline_enabled])
	if active:
		if not _selected:
			_apply_object_outline(hover_outline_color, false)
		return
	if not _selected:
		_clear_object_outline()

func register_highlight_mesh(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance == null or _highlight_meshes.has(mesh_instance):
		return
	# One mesh, ONE outline owner: the tag lets the chunk auto-outline skip meshes another target
	# already wraps (the hub-wheel bug: the crawl mouth's auto-collect grabbed the neighbouring
	# wheel's mesh, and its padded body then swallowed the wheel's hover/click ray entirely).
	mesh_instance.set_meta("outline_owner_id", get_instance_id())
	_highlight_meshes.append(mesh_instance)
	_original_overlays[mesh_instance.get_instance_id()] = mesh_instance.material_overlay
	# If the outline is already showing (mesh registered after a hover), feed the new mesh into the mask too.
	if _outline_active:
		_register_mask(_active_outline_color, _glow_active)

func get_highlight_mesh_count() -> int:
	_prune_highlight_meshes()
	return _highlight_meshes.size()

## Number of meshes this target outlines. Named "shell count" for the historical inverted-hull shells; the crisp
## outline is now the screen-space mask, so this is the count of registered outline meshes (the contract callers
## assert: a visible object registered geometry to outline).
func get_outline_shell_count() -> int:
	_prune_highlight_meshes()
	var count := 0
	for mesh_instance in _highlight_meshes:
		if mesh_instance != null and mesh_instance.mesh != null:
			count += 1
	return count

func has_active_mesh_outline() -> bool:
	return _outline_active

func has_active_outline_particles() -> bool:
	for particles in _outline_particles.values():
		if is_instance_valid(particles) and particles is GPUParticles3D and (particles as GPUParticles3D).emitting:
			return true
	return false

## A click committed an interaction with this object: the character is walking toward it (or the
## move is queued). The outline + energy glow tint to the SERVICING CHARACTER's color — the same
## ownership language as the hover grid and path ribbon. Cleared on arrival/trigger/cancel.
func begin_queued_feedback(_origin: Vector3 = Vector3.ZERO, queue_color: Color = Color(0, 0, 0, 0)) -> void:
	_selected = true
	_selection_token += 1
	var tint := queue_color if queue_color.a > 0.0 else selected_feedback_color
	_apply_object_outline(tint, true)
	_play_interaction_pulse(tint, "queued")

func complete_queued_feedback() -> void:
	_clear_queued_feedback()

func cancel_queued_feedback() -> void:
	_clear_queued_feedback()

func is_selected_feedback_active() -> bool:
	return _selected

func _clear_queued_feedback() -> void:
	_selected = false
	_selection_token += 1
	if _debug_anchor != null:
		_debug_anchor.visible = false
	# The glow always ends with the queue, but hover, reveal-all, and independent causal/tutorial
	# requests may still own the crisp outline.
	_refresh_highlight_request()


## Actual trigger result, distinct from arrival/queue completion. Interactable forwards its
## authoritative `interacted` / `interaction_rejected` signals here so a timed action does not
## celebrate merely because the character reached it.
func play_interaction_result(succeeded: bool) -> void:
	_play_interaction_pulse(
		Color(0.3, 1.0, 0.55, 1.0) if succeeded else Color(1.0, 0.16, 0.12, 1.0),
		"success" if succeeded else "rejected"
	)


func _play_interaction_pulse(tint: Color, kind: String) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	_ensure_interaction_pulse()
	if _interaction_pulse == null or _interaction_pulse_material == null:
		return
	if _interaction_pulse_tween != null and _interaction_pulse_tween.is_valid():
		_interaction_pulse_tween.kill()
	var radius := clampf(get_outline_highlight_radius(), 0.55, 3.0)
	var extents := get_outline_highlight_extents()
	var floor_y := _get_feedback_origin().y - maxf(0.0, extents.y) + 0.045
	_interaction_pulse.global_position = Vector3(_get_feedback_origin().x, floor_y, _get_feedback_origin().z)
	var start_scale := 1.32
	var end_scale := 0.92
	var duration := 0.32
	if kind == "success":
		start_scale = 0.72
		end_scale = 1.72
		duration = 0.46
	elif kind == "rejected":
		start_scale = 1.45
		end_scale = 0.78
		duration = 0.42
	_interaction_pulse.scale = Vector3.ONE * radius * start_scale
	_interaction_pulse.visible = true
	_interaction_pulse_material.albedo_color = Color(tint.r, tint.g, tint.b, 0.96)
	_interaction_pulse_material.emission = tint
	_interaction_pulse_material.emission_energy_multiplier = 5.0 if kind != "queued" else 3.8
	_interaction_pulse_tween = create_tween()
	_interaction_pulse_tween.set_trans(Tween.TRANS_QUAD)
	_interaction_pulse_tween.set_ease(Tween.EASE_OUT)
	_interaction_pulse_tween.tween_property(
		_interaction_pulse, "scale", Vector3.ONE * radius * end_scale, duration)
	_interaction_pulse_tween.parallel().tween_property(
		_interaction_pulse_material, "albedo_color:a", 0.0, duration)
	_interaction_pulse_tween.parallel().tween_property(
		_interaction_pulse_material, "emission_energy_multiplier", 0.6, duration)
	_interaction_pulse_tween.tween_callback(func() -> void:
		if _interaction_pulse != null:
			_interaction_pulse.visible = false)


func _ensure_interaction_pulse() -> void:
	if _interaction_pulse != null and is_instance_valid(_interaction_pulse):
		return
	_interaction_pulse_material = StandardMaterial3D.new()
	_interaction_pulse_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_interaction_pulse_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_interaction_pulse_material.emission_enabled = true
	_interaction_pulse_material.no_depth_test = false
	_interaction_pulse_material.render_priority = 4
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.0
	torus.rings = 28
	torus.ring_segments = 10
	_interaction_pulse = MeshInstance3D.new()
	_interaction_pulse.name = "InteractionPulse"
	_interaction_pulse.mesh = torus
	_interaction_pulse.material_override = _interaction_pulse_material
	_interaction_pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_interaction_pulse.layers = 2
	_interaction_pulse.set_meta("camera_occlusion_exempt", true)
	_interaction_pulse.visible = false
	add_child(_interaction_pulse)
	_interaction_pulse.top_level = true

## active=hover outline (glow_on=false) OR the queued energy glow (glow_on=true). The crisp outline + the morphing
## energy halo are both the screen-space mask now (OutlineMaskManager); glow_on flips the mask's fill-alpha flag.
func _apply_object_outline(color: Color, glow_on: bool) -> void:
	if not object_outline_enabled:
		return
	_active_outline_color = color
	_outline_active = true
	_glow_active = glow_on
	_register_mask(color, glow_on)

func _clear_object_outline() -> void:
	_outline_active = false
	_glow_active = false
	_unregister_mask()
	_prune_highlight_meshes()
	for mesh_instance in _highlight_meshes:
		var original = _original_overlays.get(mesh_instance.get_instance_id(), null)
		mesh_instance.material_overlay = original

## Hand the highlight meshes to the scene's OutlineMaskManager (the screen-space outline + glow). No manager
## (headless test / standalone target) is fine — the logical _outline_active/_glow_active flags still reflect state.
func _register_mask(color: Color, glow_on: bool) -> void:
	_prune_highlight_meshes()
	var manager := _get_mask_manager()
	if manager == null:
		return
	manager.register(get_instance_id(), _highlight_meshes, color, glow_on)

func _unregister_mask() -> void:
	if _mask_manager != null and is_instance_valid(_mask_manager):
		_mask_manager.unregister(get_instance_id())

func _get_mask_manager() -> OutlineMaskManager:
	if _mask_manager != null and is_instance_valid(_mask_manager):
		return _mask_manager
	if Engine.is_editor_hint() or not is_inside_tree():
		return null
	_mask_manager = OutlineMaskManager.find_for(self)
	return _mask_manager

## The QUEUED energy glow is now the screen-space mask's noise-morphed halo (OutlineMaskManager), keyed off the
## queued fill-alpha flag — no more inverted-hull emission shell. This is the logical "glow on" state.
func has_active_glow() -> bool:
	return _glow_active

func _play_outline_particles() -> void:
	if not outline_particles_enabled:
		return
	_prune_highlight_meshes()
	for mesh_instance in _highlight_meshes:
		var particles := _ensure_outline_particles(mesh_instance)
		if particles == null:
			continue
		_sync_outline_particles(mesh_instance, particles)
		particles.amount = maxi(1, outline_particles_per_mesh)
		particles.lifetime = maxf(0.1, selected_feedback_duration)
		var process_material := particles.process_material as ParticleProcessMaterial
		if process_material != null:
			process_material.color = selected_feedback_color
		_set_particle_draw_color(particles, selected_feedback_color, 8.0)
		_restart_particle_emitter(particles)

func _stop_outline_particles() -> void:
	for particles in _outline_particles.values():
		if is_instance_valid(particles) and particles is GPUParticles3D:
			_clear_particle_emitter(particles as GPUParticles3D)

func _ensure_outline_particles(mesh_instance: MeshInstance3D) -> GPUParticles3D:
	if mesh_instance == null or mesh_instance.mesh == null:
		return null
	var mesh_id := mesh_instance.get_instance_id()
	var existing = _outline_particles.get(mesh_id, null)
	if existing is GPUParticles3D and is_instance_valid(existing):
		return existing

	var particles := GPUParticles3D.new()
	particles.name = "OutlineParticles"
	particles.amount = maxi(1, outline_particles_per_mesh)
	particles.lifetime = maxf(0.1, selected_feedback_duration)
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.emitting = false
	particles.visible = false
	# Ride the mesh's world transform (no top_level): emission points authored in
	# mesh-local space then land on the surface at the right world position/scale,
	# and follow the object if it moves.
	particles.top_level = false
	particles.local_coords = true
	particles.visibility_aabb = AABB(Vector3(-6.0, -6.0, -6.0), Vector3(12.0, 12.0, 12.0))

	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.065
	particle_mesh.height = 0.13
	particle_mesh.material = _make_particle_draw_material(selected_feedback_color, 8.0)
	particles.draw_pass_1 = particle_mesh

	var process_material := ParticleProcessMaterial.new()
	# Emit from the OUTLINE itself: the outline shader is an inverted hull — each mesh vertex
	# pushed out along its normal by outline_width — so we push the surface emission points out
	# by the same amount. The particles then originate ON the outline shell (where the white
	# edge is drawn) and drift outward, appearing to emanate from the outline. We can't read the
	# GPU shader's output, but its geometry is pure normal-offset math we already have here.
	var emission := _build_surface_emission(mesh_instance.mesh, outline_particles_per_mesh)
	if int(emission["count"]) > 0:
		var push := maxf(selected_object_outline_width, hover_object_outline_width)
		var src_pos: PackedVector3Array = emission["positions"]
		var src_nrm: PackedVector3Array = emission["normals"]
		var shell_pos := PackedVector3Array()
		shell_pos.resize(src_pos.size())
		for i in range(src_pos.size()):
			shell_pos[i] = src_pos[i] + src_nrm[i] * push
		process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS
		process_material.emission_point_count = int(emission["count"])
		process_material.emission_point_texture = _emission_points_texture(shell_pos)
		process_material.emission_normal_texture = _emission_points_texture(emission["normals"])
	else:
		# Degenerate mesh (no triangles): a sphere around the object still spreads.
		var aabb := mesh_instance.mesh.get_aabb()
		process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process_material.emission_sphere_radius = maxf(0.2, aabb.size.length() * 0.5)
	process_material.direction = Vector3.UP
	process_material.spread = 180.0
	process_material.initial_velocity_min = 0.01
	process_material.initial_velocity_max = 0.08
	process_material.gravity = Vector3.ZERO
	# Push particles outward from the object centre — they spawn on the outline shell and drift
	# away from it, so they read as emanating FROM the outline rather than sitting on the surface.
	# Reliable regardless of the DIRECTED_POINTS normal-sampling bug (it's centre-relative).
	process_material.radial_accel_min = 0.12
	process_material.radial_accel_max = 0.3
	process_material.scale_min = 0.1
	process_material.scale_max = 0.24
	process_material.color = selected_feedback_color
	particles.process_material = process_material

	mesh_instance.add_child(particles)
	_outline_particles[mesh_id] = particles
	_sync_outline_particles(mesh_instance, particles)
	return particles

func _sync_outline_particles(mesh_instance: MeshInstance3D, particles: GPUParticles3D) -> void:
	if mesh_instance == null or particles == null or mesh_instance.mesh == null:
		return
	# Sit at the mesh's local origin so it inherits the mesh's world transform; the
	# emission points (mesh-local) then map straight onto the surface.
	particles.transform = Transform3D.IDENTITY
	var aabb := mesh_instance.mesh.get_aabb()
	var margin := Vector3.ONE * (selected_object_outline_width + 0.5)
	particles.visibility_aabb = AABB(aabb.position - margin, aabb.size + margin * 2.0)

# Low-discrepancy constants for even, deterministic surface sampling (no RNG, so it
# stays replay-safe and clear of the wall-clock-RNG lint).
const _SURFACE_PHI := 0.6180339887498949
const _SURFACE_R2_A := 0.7548776662466927
const _SURFACE_R2_B := 0.5698402909980532

## Area-weighted, deterministic sample of a mesh surface. Returns mesh-local
## positions plus per-point face normals (one entry per requested sample) so
## particles can emit from the object's outline instead of one clustered point.
## count == 0 means the mesh had no triangles to sample.
func _build_surface_emission(mesh: Mesh, sample_count: int) -> Dictionary:
	var count := maxi(1, sample_count)
	var v0 := PackedVector3Array()
	var v1 := PackedVector3Array()
	var v2 := PackedVector3Array()
	var nrm := PackedVector3Array()
	var cum_area := PackedFloat32Array()
	var total := 0.0
	for s in range(mesh.get_surface_count()):
		# PrimitiveMesh (BoxMesh, etc.) lacks surface_get_primitive_type and is always
		# triangles; ArrayMesh exposes it, so skip any non-triangle surface there.
		if mesh.has_method("surface_get_primitive_type") and mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(s)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		@warning_ignore("integer_division")
		var tri_count: int = (verts.size() / 3) if idx.is_empty() else (idx.size() / 3)
		for t in range(tri_count):
			var a: Vector3
			var b: Vector3
			var c: Vector3
			if idx.is_empty():
				a = verts[t * 3]
				b = verts[t * 3 + 1]
				c = verts[t * 3 + 2]
			else:
				a = verts[idx[t * 3]]
				b = verts[idx[t * 3 + 1]]
				c = verts[idx[t * 3 + 2]]
			var cross := (b - a).cross(c - a)
			var double_area := cross.length()
			if double_area <= 0.0000001:
				continue
			total += double_area * 0.5
			v0.append(a)
			v1.append(b)
			v2.append(c)
			nrm.append(cross / double_area)
			cum_area.append(total)
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	if v0.is_empty() or total <= 0.0:
		return {"positions": positions, "normals": normals, "count": 0}
	for i in range(count):
		# Pick a triangle weighted by area via a low-discrepancy sweep, then an even
		# barycentric point inside it via an R2 low-discrepancy pair.
		var pick := fposmod(float(i) * _SURFACE_PHI, 1.0) * total
		var lo := 0
		var hi := cum_area.size() - 1
		while lo < hi:
			var mid := (lo + hi) >> 1
			if cum_area[mid] < pick:
				lo = mid + 1
			else:
				hi = mid
		var r1 := fposmod(float(i) * _SURFACE_R2_A, 1.0)
		var r2 := fposmod(float(i) * _SURFACE_R2_B, 1.0)
		var su := sqrt(r1)
		positions.append(v0[lo] * (1.0 - su) + v1[lo] * (su * (1.0 - r2)) + v2[lo] * (su * r2))
		normals.append(nrm[lo])
	return {"positions": positions, "normals": normals, "count": count}

## Pack points into a 1-row RGBF texture for ParticleProcessMaterial point emission.
func _emission_points_texture(points: PackedVector3Array) -> ImageTexture:
	var n := maxi(1, points.size())
	var image := Image.create(n, 1, false, Image.FORMAT_RGBF)
	for i in range(points.size()):
		var p := points[i]
		image.set_pixel(i, 0, Color(p.x, p.y, p.z))
	return ImageTexture.create_from_image(image)

func _make_particle_draw_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

func _set_particle_draw_color(particles: GPUParticles3D, color: Color, energy: float) -> void:
	if particles == null or not (particles.draw_pass_1 is PrimitiveMesh):
		return
	var mesh := particles.draw_pass_1 as PrimitiveMesh
	if mesh.material is StandardMaterial3D:
		var material := mesh.material as StandardMaterial3D
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = energy

func _restart_particle_emitter(particles: GPUParticles3D) -> void:
	if particles == null:
		return
	particles.visible = true
	particles.emitting = false
	particles.restart()
	particles.emitting = true

func _clear_particle_emitter(particles: GPUParticles3D) -> void:
	if particles == null:
		return
	particles.emitting = false
	particles.visible = false
	particles.restart()
	particles.emitting = false

func _show_debug_anchor(world_position: Vector3) -> void:
	if not debug_particle_anchor_enabled:
		return
	_ensure_debug_anchor()
	_debug_anchor.global_position = world_position
	_debug_anchor.visible = true

func _ensure_debug_anchor() -> void:
	if _debug_anchor != null:
		return
	_debug_anchor = MeshInstance3D.new()
	_debug_anchor.name = "SelectedParticleAnchor"
	_debug_anchor.top_level = true
	_debug_anchor.visible = false
	var anchor_mesh := SphereMesh.new()
	anchor_mesh.radius = 0.16
	anchor_mesh.height = 0.32
	anchor_mesh.material = _make_particle_draw_material(Color(0.1, 0.8, 1.0, 1.0), 10.0)
	_debug_anchor.mesh = anchor_mesh
	add_child(_debug_anchor)

func _get_feedback_origin() -> Vector3:
	_prune_highlight_meshes()
	if not _highlight_meshes.is_empty():
		var total := Vector3.ZERO
		var count := 0
		for mesh_instance in _highlight_meshes:
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			var aabb := mesh_instance.mesh.get_aabb()
			total += mesh_instance.to_global(aabb.position + aabb.size * 0.5)
			count += 1
		if count > 0:
			return total / float(count)
	return get_outline_highlight_origin()

func _prune_highlight_meshes() -> void:
	for i in range(_highlight_meshes.size() - 1, -1, -1):
		var mesh_instance := _highlight_meshes[i]
		if not is_instance_valid(mesh_instance):
			_highlight_meshes.remove_at(i)

func get_outline_highlight_radius() -> float:
	if outline_highlight_radius > 0.0:
		return outline_highlight_radius
	var extents := get_outline_highlight_extents()
	if extents != Vector3.ZERO:
		return maxf(0.35, extents.length())
	var visual := _find_visual_mesh()
	if visual != null and visual.mesh != null:
		var aabb := visual.mesh.get_aabb()
		return maxf(0.35, aabb.size.length() * 0.5)
	return 1.0

func get_outline_highlight_extents() -> Vector3:
	if outline_highlight_extents != Vector3.ZERO:
		return outline_highlight_extents
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null:
		if shape_node.shape is BoxShape3D:
			return (shape_node.shape as BoxShape3D).size * 0.5
		if shape_node.shape is SphereShape3D:
			var radius := (shape_node.shape as SphereShape3D).radius
			return Vector3.ONE * radius
	var visual := _find_visual_mesh()
	if visual != null and visual.mesh != null:
		return visual.mesh.get_aabb().size * 0.5
	return Vector3.ZERO

func get_outline_highlight_origin() -> Vector3:
	var visual := _find_visual_mesh()
	if visual != null and visual.mesh != null:
		var aabb := visual.mesh.get_aabb()
		return visual.to_global(aabb.position + aabb.size * 0.5)
	if get_outline_highlight_extents() != Vector3.ZERO:
		return global_position
	return global_position + Vector3(0.0, outline_highlight_height, 0.0)

func get_interaction_target_position(_from_position: Vector3 = Vector3.ZERO, requested_position: Vector3 = Vector3.INF) -> Vector3:
	if has_meta("interaction_target_position"):
		var target_position = get_meta("interaction_target_position")
		if target_position is Vector3:
			return target_position
		if target_position is Array and (target_position as Array).size() >= 3:
			return Vector3(
				float((target_position as Array)[0]),
				float((target_position as Array)[1]),
				float((target_position as Array)[2])
			)
	var delegate := _valid_interaction_delegate()
	if delegate != null:
		if delegate.has_method("get_interaction_target_position"):
			var delegated_position = delegate.call("get_interaction_target_position", _from_position, requested_position)
			if delegated_position is Vector3:
				return delegated_position
		if delegate is Node3D:
			var delegate_node := delegate as Node3D
			return delegate_node.global_position
	if requested_position != Vector3.INF:
		return requested_position
	return global_position

func on_interaction_arrived() -> void:
	var delegate := _valid_interaction_delegate()
	if delegate != null and delegate.has_method("on_interaction_arrived"):
		delegate.call("on_interaction_arrived")

func _find_visual_mesh() -> MeshInstance3D:
	var visual := get_node_or_null("Visual") as MeshInstance3D
	if visual != null:
		return visual
	return find_child("*", true, false) as MeshInstance3D

func _valid_interaction_delegate() -> Node:
	if _interaction_delegate != null and is_instance_valid(_interaction_delegate):
		return _interaction_delegate
	if interaction_delegate_path != NodePath(""):
		_interaction_delegate = get_node_or_null(interaction_delegate_path)
		if _interaction_delegate != null and is_instance_valid(_interaction_delegate):
			return _interaction_delegate
	return null
