@tool
class_name OutlineSurfaceTarget
extends StaticBody3D

## Pickable room object with object-local outline and selected feedback.

const PLAYER_OBSERVATION_PRESENTER_GROUP := &"player_observation_presenters"
const PLAYER_OBSERVATION_PIXEL_OFFSETS: Array[Vector2] = [
	Vector2.ZERO,
	Vector2(0.0, -8.0), Vector2(0.0, 8.0),
	Vector2(-8.0, 0.0), Vector2(8.0, 0.0),
	Vector2(0.0, -16.0), Vector2(0.0, 16.0),
	Vector2(-16.0, 0.0), Vector2(16.0, 0.0),
]
const INTERACTION_RESULT_MAX_SURFACE_SAMPLES := 96
## Saturated enough to remain visibly green after the Compatibility tonemapper;
## a mint-blue mix clips both G and B in bright generated scenes.
const INTERACTION_SUCCESS_TINT := Color(0.08, 0.9, 0.12, 1.0)
## How long a completed result holds its tint on the outline before the channel is released.
const RESULT_OUTLINE_HOLD_SECONDS := 0.55

@export var hover_enabled := true
@export var hover_outline_color := Color.WHITE
@export var selected_feedback_color := Color(1.0, 0.62, 0.12, 1.0)
@export var object_outline_enabled := true
# Outline widths are SCREEN-SPACE (fraction of viewport height), constant at any distance — see the shader.
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
## The real world-space collision point for the synchronous pointer command now
## being delivered. A partially HUD-occluded object can have a hidden center but
## a visible clickable edge; immediate success/refusal feedback must appear at
## the point the player could actually see and choose.
var _pointer_result_origin_override := Vector3.INF
## Whether this rendered wrapper currently represents an actionable command
## surface.  This is deliberately separate from `hover_enabled`: consumed and
## hard-disabled Interactables keep their mesh, collision body, presenter token,
## and result-pulse surface, but must stop winning pointer picking.
var _interaction_command_enabled := true
var _pointer_hover_active := false
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
# The crisp outline is a SCREEN-SPACE mask (OutlineMaskManager) — clean on flat-shaded meshes, constant width
# at any distance. _outline_active is the logical "outline showing" flag (what has_active_mesh_outline reports);
# the manager does the actual rendering. Null manager (headless test / standalone) => flag only, no render.
var _outline_active := false
var _glow_active := false      # the QUEUED energy glow (set on begin_queued_feedback); has_active_glow() reports it
var _active_outline_color := Color.WHITE
var _mask_manager: OutlineMaskManager = null
var _highlight_requested := false
var _external_highlight_reasons := {}
var _interaction_pulse_tween: Tween = null
var _interaction_pulse_generation := 0
var _interaction_presentation_serial := 0
## The authoritative outcome that minted the current serial, even when a
## headless renderer cannot instantiate its actual halo. Observation still
## requires `result` + `visible`; command ordering uses this field only to avoid
## overwriting a synchronous result with a later queued pulse.
var _interaction_presentation_authority_result := ""
var _interaction_presentation_result := ""
var _interaction_presentation_visible := false

signal outline_hovered(interactable: Node)
signal outline_unhovered(interactable: Node)
signal outline_selected(interactable: Node)
signal interaction_requested(interactable: Node, world_position: Vector3)

func _ready() -> void:
	if interaction_delegate_path != NodePath(""):
		_interaction_delegate = get_node_or_null(interaction_delegate_path)
	collision_layer = 4 if hover_enabled else 0
	collision_mask = 0
	_sync_command_availability_from_delegate()
	input_ray_pickable = hover_enabled and _interaction_command_enabled
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
	_refresh_player_observation_presenter_registration()


func _exit_tree() -> void:
	if _interaction_pulse_tween != null and _interaction_pulse_tween.is_valid():
		_interaction_pulse_tween.kill()

func _on_mouse_entered() -> void:
	if GridWorld._fx_debug:
		GridWorld._pf_trace("[outline] HIT surface-target '%s' (hover_enabled=%s managed=%s layer=%d pickable=%s)" % [
			name, hover_enabled, _feedback_managed, collision_layer, input_ray_pickable])
	if not hover_enabled or not _interaction_command_enabled:
		return
	_pointer_hover_active = true
	if not _feedback_managed:
		set_hover_feedback(true)
	outline_hovered.emit(self)

func _on_mouse_exited() -> void:
	_clear_pointer_hover()

func _on_input_event(_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if not hover_enabled or not _interaction_command_enabled:
		return
	if event is InputEventMouseButton:
		# The `command` action (right mouse) is the interact command (mirror of Interactable). A `select`
		# (left) click over the mesh is NEVER an interaction — it falls through to a plain move/select.
		if event.is_action_pressed("command"):
			var viewport := get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
			submit_pointer_command(event_position)


## Production semantic edge used by the classified short-RMB controller and by
## ordinary physics-object input. Both paths retain this visible surface as the
## exact source of the interaction request.
func submit_pointer_command(event_position: Vector3 = Vector3.INF) -> bool:
	if not hover_enabled:
		return false
	# A short command is captured from the real physics hit before it is submitted
	# from the FIFO.  The delegate may be consumed in between those two production
	# steps.  Reject that stale capture on this exact visible target so the player
	# gets a red result pulse instead of a silent no-op.
	if not _interaction_command_enabled:
		play_interaction_result(false)
		return false
	# The wrapper owns the rendered/pickable surface, while a linked delegate owns
	# the gameplay interaction. Route the semantic command through that canonical
	# public seam so dynamically created wrappers do not depend on a second
	# CharacterInteractionController signal binding, and so arrival invokes the
	# delegate that can actually trigger. The delegate's outline_selected signal
	# already drives this wrapper through Interactable.set_outline_target(); emitting
	# both would start the same queued pulse twice and could erase an immediate
	# result. Bare surface targets retain their original direct command contract.
	var delegate := _valid_interaction_delegate()
	if delegate != null and delegate.has_method("submit_pointer_command"):
		var previous_result_origin := _pointer_result_origin_override
		if event_position.is_finite():
			_pointer_result_origin_override = event_position
		var accepted := bool(delegate.call("submit_pointer_command", event_position))
		_pointer_result_origin_override = previous_result_origin
		return accepted
	interaction_requested.emit(
		self, event_position if event_position.is_finite() else global_position)
	outline_selected.emit(self)
	return true

func set_interaction_delegate(delegate: Node) -> void:
	_interaction_delegate = delegate
	_sync_command_availability_from_delegate()
	_refresh_player_observation_presenter_registration()

func get_interaction_delegate() -> Node:
	return _valid_interaction_delegate()


## Mirror a linked gameplay delegate's hard availability without retracting the
## rendered object or its collision truth.  `input_ray_pickable=false` makes both
## viewport picking and Player's production command ray pass through to typed
## ground, while the collision layer remains available to non-input diagnostics.
func set_interaction_command_enabled(active: bool) -> void:
	var changed := _interaction_command_enabled != active
	_interaction_command_enabled = active
	input_ray_pickable = hover_enabled and _interaction_command_enabled
	if changed and not active:
		_clear_pointer_hover()
	_refresh_player_observation_presenter_registration()


func is_interaction_command_enabled() -> bool:
	return _interaction_command_enabled


func _sync_command_availability_from_delegate() -> void:
	var delegate := _valid_interaction_delegate()
	if delegate != null and delegate.has_method("is_pointer_command_available"):
		set_interaction_command_enabled(
			bool(delegate.call("is_pointer_command_available")))
	else:
		set_interaction_command_enabled(true)


func _clear_pointer_hover() -> void:
	if not _pointer_hover_active:
		return
	_pointer_hover_active = false
	if not _feedback_managed:
		set_hover_feedback(false)
	outline_unhovered.emit(self)

func play_selected_feedback(origin: Vector3 = Vector3.ZERO, use_world_origin := false) -> void:
	# Deliberate no-op: selection feedback is the queued energy glow, never a particle burst.
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
	# already wraps — otherwise an auto-collect can grab a neighbouring object's mesh, and its
	# padded body then swallows that object's hover/click ray entirely.
	mesh_instance.set_meta("outline_owner_id", get_instance_id())
	_highlight_meshes.append(mesh_instance)
	_original_overlays[mesh_instance.get_instance_id()] = mesh_instance.material_overlay
	_refresh_player_observation_presenter_registration()
	# If the outline is already showing (mesh registered after a hover), feed the new mesh into the mask too.
	if _outline_active:
		_register_mask(_active_outline_color, _glow_active)

func get_highlight_mesh_count() -> int:
	_prune_highlight_meshes()
	return _highlight_meshes.size()

## The registered meshes themselves — the geometry a cosmetic system (juice
## squash/rustle) animates. Callers get a copy; ownership stays here.
func get_highlight_meshes() -> Array:
	_prune_highlight_meshes()
	return _highlight_meshes.duplicate()


## Public accessibility/testing surface for the geometry a player can actually
## see and hover. Collision alone is deliberately insufficient: an invisible
## Area/Body may still be pickable, but it must never become a policy affordance.
## The observation adapter still performs camera, framebuffer/occlusion, UI, and
## exact production-pointer checks on these nodes before exposing an opaque token.
func get_player_observation_render_nodes() -> Array[Node3D]:
	_prune_highlight_meshes()
	var render_nodes: Array[Node3D] = []
	for mesh_instance in _highlight_meshes:
		if _render_node_has_visible_surface(mesh_instance):
			render_nodes.append(mesh_instance)
	if not render_nodes.is_empty():
		return render_nodes

	# Some small authored interactables intentionally use a visible tutorial
	# billboard as their only rendered target. Accept that fallback only while the
	# exact Label3D is in-tree, non-empty, and visibly modulated.
	var delegate := _valid_interaction_delegate()
	if delegate != null and delegate.has_method("get_tutorial_label_node"):
		var label_v: Variant = delegate.call("get_tutorial_label_node")
		if label_v is Label3D and _render_node_has_visible_surface(label_v as Label3D):
			render_nodes.append(label_v as Label3D)
	return render_nodes


## Screen-space discovery owned by the same production presentation object that
## draws and receives pointer input. Automated observers iterate only the
## explicit presenter group and never walk arbitrary scene nodes or inspect
## their transforms. Exact production pointer hit, UI blocking, and live
## occlusion checks remain mandatory after these candidate pixels are returned.
func get_player_observation_screen_candidates(
		camera: Camera3D, viewport: Viewport
	) -> Array[Vector2]:
	return _screen_candidates_for_render_nodes(
		get_player_observation_render_nodes(), camera, viewport)


func _refresh_player_observation_presenter_registration() -> void:
	if not is_inside_tree():
		return
	# Every enabled OutlineSurfaceTarget is itself a production command surface:
	# it owns a pickable StaticBody and emits interaction_requested. A linked
	# delegate refines the verb/receipt but is not required for direct targets.
	# A PushTarget deliberately disables this wrapper's own hover ray and routes
	# input through its linked delegate, but the wrapper still owns the visible
	# crate surface. Keep that legitimate presenter registered as well.
	var should_register := has_signal(&"interaction_requested") and (
		input_ray_pickable or _valid_interaction_delegate() != null)
	if should_register and not is_in_group(PLAYER_OBSERVATION_PRESENTER_GROUP):
		add_to_group(PLAYER_OBSERVATION_PRESENTER_GROUP)
	elif not should_register and is_in_group(PLAYER_OBSERVATION_PRESENTER_GROUP):
		remove_from_group(PLAYER_OBSERVATION_PRESENTER_GROUP)


func _screen_candidates_for_render_nodes(
		render_nodes: Array[Node3D], camera: Camera3D, viewport: Viewport
	) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	if camera == null or viewport == null or not camera.is_inside_tree():
		return candidates
	var visible_rect := viewport.get_visible_rect()
	var world_points: Array[Vector3] = []
	for render_node in render_nodes:
		if render_node == null or not is_instance_valid(render_node) \
				or not render_node.is_visible_in_tree():
			continue
		world_points.append(render_node.global_position)
		if render_node is MeshInstance3D:
			var mesh_instance := render_node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			var bounds := mesh_instance.get_aabb()
			world_points.append(mesh_instance.global_transform * bounds.get_center())
			for endpoint_index in range(8):
				world_points.append(
					mesh_instance.global_transform * bounds.get_endpoint(endpoint_index))
	for world_point in world_points:
		if camera.is_position_behind(world_point):
			continue
		var projected := camera.unproject_position(world_point)
		for offset in PLAYER_OBSERVATION_PIXEL_OFFSETS:
			var candidate := projected + offset
			if visible_rect.has_point(candidate) and not candidates.has(candidate):
				candidates.append(candidate)
	return candidates


func _render_node_has_visible_surface(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node) or not node.is_visible_in_tree():
		return false
	if node is Label3D:
		var label := node as Label3D
		return not str(label.text).strip_edges().is_empty() and label.modulate.a > 0.01
	if not (node is MeshInstance3D):
		return false
	var mesh_instance := node as MeshInstance3D
	if mesh_instance.mesh == null or mesh_instance.transparency >= 0.99:
		return false
	if _material_has_visible_surface(mesh_instance.material_override):
		return true
	var saw_surface_material := false
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var material := mesh_instance.get_active_material(surface_index)
		if material == null:
			continue
		saw_surface_material = true
		if _material_has_visible_surface(material):
			return true
	# A mesh with no explicit material still renders with Godot's fallback material.
	return not saw_surface_material


func _material_has_visible_surface(material: Material) -> bool:
	if material == null:
		return false
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		# With no target-ID framebuffer pass, dynamic alpha and camera-distance
		# fades cannot be distinguished from collision-only geometry. Only the
		# fully opaque, non-fading BaseMaterial path is independently safe here.
		return base.albedo_color.a > 0.01 \
			and base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and base.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED \
			and not base.proximity_fade_enabled
	# A custom shader can discard every fragment or drive ALPHA from arbitrary
	# uniforms/textures. Collision, a material reference, and even a pointer ray
	# therefore cannot prove that a human can see it. Until a shader-backed target
	# supplies independently verified render evidence, fail closed instead of
	# manufacturing a policy affordance from hidden gameplay geometry.
	return false

## Number of meshes this target outlines: the registered outline meshes fed to the screen-space
## mask. This is the contract callers assert — a visible object registered geometry to outline.
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
	# A newly queued interaction supersedes any result still presented on this object.
	_interaction_presentation_authority_result = ""
	_interaction_presentation_result = ""
	_interaction_presentation_visible = false
	_play_interaction_pulse(tint, "queued", -1)

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
	_interaction_presentation_serial += 1
	var presentation_serial := _interaction_presentation_serial
	var result_kind := "success" if succeeded else "rejected"
	_interaction_presentation_authority_result = result_kind
	var rendered := _play_interaction_pulse(
		INTERACTION_SUCCESS_TINT if succeeded else Color(1.0, 0.16, 0.12, 1.0),
		result_kind,
		presentation_serial
	)
	_interaction_presentation_result = result_kind if rendered else ""
	_interaction_presentation_visible = rendered


## Target-specific presentation receipt. The monotonically increasing serial
## distinguishes this object's latest authoritative trigger result from ambient
## HUD/consequence churn. `visible` is true only while the result tint actually
## rides rendered geometry: the object's own highlight meshes, registered into
## the scene's outline mask at the result colour -- the one shape language.
func get_player_interaction_presentation() -> Dictionary:
	return {
		"presentation_serial": _interaction_presentation_serial,
		"authority_result": _interaction_presentation_authority_result,
		"result": _interaction_presentation_result,
		"visible": _interaction_presentation_visible \
			and _outline_active and not _presentation_meshes().is_empty(),
	}


## The exact geometry carrying the current green/red result: the highlighted
## meshes whose silhouette the mask tints. Presentation observers must still
## prove a node is inside the current camera, on-screen, and associated with the
## same production pointer affordance before admitting a result cue. The boolean
## receipt above is deliberately not sufficient alone.
func get_player_interaction_presentation_render_nodes() -> Array[Node3D]:
	var render_nodes: Array[Node3D] = []
	if _interaction_presentation_visible \
			and _interaction_presentation_result in ["success", "rejected"]:
		for mesh_instance in _presentation_meshes():
			render_nodes.append(mesh_instance)
	return render_nodes


## The valid, in-tree, visible subset of the registered highlight meshes.
func _presentation_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mesh_v in _highlight_meshes:
		var mesh_instance := mesh_v as MeshInstance3D
		if mesh_instance != null and is_instance_valid(mesh_instance) \
				and mesh_instance.is_inside_tree() \
				and mesh_instance.is_visible_in_tree() \
				and mesh_instance.mesh != null:
			out.append(mesh_instance)
	return out


## Candidate pixels for the actual transient green/red geometry. This separate
## surface lets the observer prove the cue itself remains in the current view;
## it may not infer that from the source object's earlier visibility.
func get_player_interaction_presentation_screen_candidates(
		camera: Camera3D, viewport: Viewport
	) -> Array[Vector2]:
	# The result rides the silhouette, and a silhouette's pixels sit on the mesh
	# boundary -- so candidate pixels are projected samples of the highlight
	# meshes' own vertices, which land exactly where the mask draws. A generic
	# centre probe could land inside a large body, far from any outline pixel.
	var candidates: Array[Vector2] = []
	if camera == null or viewport == null or not camera.is_inside_tree():
		return candidates
	var visible_rect := viewport.get_visible_rect()
	for world_point_v in get_player_interaction_presentation_world_candidates():
		var world_point := world_point_v as Vector3
		if camera.is_position_behind(world_point):
			continue
		var projected := camera.unproject_position(world_point)
		if visible_rect.has_point(projected) and not candidates.has(projected):
			candidates.append(projected)
	return candidates


## The same silhouette samples in world space, so an observer can depth-test each candidate at its
## exact surface point: the mask composites the outline regardless of scene occluders, and pixels
## alone therefore cannot prove the PLAYER can see the object.
func get_player_interaction_presentation_world_candidates() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for mesh_instance in get_player_interaction_presentation_render_nodes():
		var mesh_node := mesh_instance as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		for surface_index in range(mesh_node.mesh.get_surface_count()):
			var arrays := mesh_node.mesh.surface_get_arrays(surface_index)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if vertices.is_empty():
				continue
			var stride := maxi(1, ceili(float(vertices.size()) \
				/ float(INTERACTION_RESULT_MAX_SURFACE_SAMPLES)))
			for vertex_index in range(0, vertices.size(), stride):
				points.append(mesh_node.global_transform * vertices[vertex_index])
	return points


func _play_interaction_pulse(
		tint: Color, kind: String, _presentation_serial := -1
	) -> bool:
	# THE RESULT RIDES THE OBJECT'S OWN SILHOUETTE. The highlight law has ONE shape language: the
	# screen-space mask Sobel IS the shape, tinted white for hover and the servicing character's
	# colour when queued; a result is one more tint on that same channel. A separate fixed ring
	# would ignore the object's shape and speak a saturated green nothing else in the game uses —
	# and any renderer-specific stand-in geometry would teach web and desktop players two
	# different feedback languages.
	# This is the single overridable ATTESTATION SEAM: headless fixtures replace it to stand in
	# for an unavailable renderer, relying on its guards and return contract.
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return false
	_apply_object_outline(tint, true)
	if not (kind in ["success", "rejected"]):
		return true
	# Hold the result tint for a readable beat, then hand the outline back to whoever still owns it.
	# The timer is a tween BOUND TO THIS NODE, never a tree timer: a delayed callback that touches
	# scene nodes must die with the scene.
	if _interaction_pulse_tween != null and _interaction_pulse_tween.is_valid():
		_interaction_pulse_tween.kill()
	_interaction_pulse_generation += 1
	var generation := _interaction_pulse_generation
	_interaction_pulse_tween = create_tween()
	_interaction_pulse_tween.tween_interval(RESULT_OUTLINE_HOLD_SECONDS)
	_interaction_pulse_tween.tween_callback(func() -> void:
		if generation != _interaction_pulse_generation:
			return
		_interaction_presentation_visible = false
		if _selected:
			_apply_object_outline(selected_feedback_color, true)
		else:
			_refresh_highlight_request())
	return true


## active=hover outline (glow_on=false) OR the queued energy glow (glow_on=true). The crisp outline + the morphing
## energy halo are both the screen-space mask (OutlineMaskManager); glow_on flips the mask's fill-alpha flag.
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

## The QUEUED energy glow is the screen-space mask's noise-morphed halo (OutlineMaskManager), keyed off the
## queued fill-alpha flag. This is the logical "glow on" state.
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
