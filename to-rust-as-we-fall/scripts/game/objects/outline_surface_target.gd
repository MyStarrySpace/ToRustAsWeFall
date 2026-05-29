@tool
class_name OutlineSurfaceTarget
extends StaticBody3D

const OBJECT_OUTLINE_SHADER := preload("res://resources/object_outline_feedback.gdshader")

## Pickable room object with object-local outline and selected feedback.

@export var hover_enabled := true
@export var hover_outline_color := Color.WHITE
@export var selected_feedback_color := Color(1.0, 0.62, 0.12, 1.0)
@export var object_outline_enabled := true
@export var hover_object_outline_width := 0.08
@export var selected_object_outline_width := 0.12
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
var _outline_shells := {}
var _outline_particles := {}
var _hovered := false
var _selected := false
var _feedback_managed := false
var _selection_token := 0

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
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
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
	if not selected_particles_enabled:
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
	_hovered = active
	if active:
		if not _selected:
			_apply_object_outline(hover_outline_color, hover_object_outline_width, 1.0)
		return
	if not _selected:
		_clear_object_outline()

func register_highlight_mesh(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance == null or _highlight_meshes.has(mesh_instance):
		return
	_highlight_meshes.append(mesh_instance)
	_original_overlays[mesh_instance.get_instance_id()] = mesh_instance.material_overlay
	_ensure_outline_shell(mesh_instance)

func get_highlight_mesh_count() -> int:
	_prune_highlight_meshes()
	return _highlight_meshes.size()

func get_outline_shell_count() -> int:
	_prune_highlight_meshes()
	return _outline_shells.size()

func has_active_mesh_outline() -> bool:
	_prune_highlight_meshes()
	for mesh_instance in _highlight_meshes:
		var shell := _get_outline_shell(mesh_instance)
		if shell != null and shell.visible and shell.material_override is ShaderMaterial:
			var material := shell.material_override as ShaderMaterial
			if material.shader == OBJECT_OUTLINE_SHADER:
				return true
	return false

func has_active_outline_particles() -> bool:
	for particles in _outline_particles.values():
		if is_instance_valid(particles) and particles is GPUParticles3D and (particles as GPUParticles3D).emitting:
			return true
	return false

func begin_queued_feedback(_origin: Vector3 = Vector3.ZERO) -> void:
	_selected = true
	_selection_token += 1
	_apply_object_outline(selected_feedback_color, selected_object_outline_width, selected_object_glow_strength)
	_play_outline_particles()
	play_selected_feedback()

func complete_queued_feedback() -> void:
	_clear_queued_feedback()

func cancel_queued_feedback() -> void:
	_clear_queued_feedback()

func is_selected_feedback_active() -> bool:
	return _selected

func _clear_queued_feedback() -> void:
	_selected = false
	_selection_token += 1
	_stop_outline_particles()
	if _selected_particles != null:
		_clear_particle_emitter(_selected_particles)
	if _debug_anchor != null:
		_debug_anchor.visible = false
	if _hovered:
		_apply_object_outline(hover_outline_color, hover_object_outline_width, 1.0)
	else:
		_clear_object_outline()

func _apply_object_outline(color: Color, width: float, glow_strength: float) -> void:
	if not object_outline_enabled:
		return
	_prune_highlight_meshes()
	for mesh_instance in _highlight_meshes:
		var shell := _ensure_outline_shell(mesh_instance)
		if shell == null:
			continue
		var material := shell.material_override as ShaderMaterial
		if material == null:
			material = _create_outline_material()
			shell.material_override = material
		material.set_shader_parameter("outline_color", color)
		material.set_shader_parameter("outline_width", width)
		material.set_shader_parameter("glow_strength", glow_strength)
		shell.visible = true

func _clear_object_outline() -> void:
	_prune_highlight_meshes()
	for mesh_instance in _highlight_meshes:
		var shell := _get_outline_shell(mesh_instance)
		if shell != null:
			shell.visible = false
		var original = _original_overlays.get(mesh_instance.get_instance_id(), null)
		mesh_instance.material_overlay = original

func _ensure_outline_shell(mesh_instance: MeshInstance3D) -> MeshInstance3D:
	if mesh_instance == null or mesh_instance.mesh == null:
		return null
	var existing := _get_outline_shell(mesh_instance)
	if existing != null:
		return existing

	var shell := MeshInstance3D.new()
	shell.name = "ObjectOutlineShell"
	shell.mesh = mesh_instance.mesh
	shell.visible = false
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.extra_cull_margin = maxf(mesh_instance.extra_cull_margin, 4.0)
	shell.layers = mesh_instance.layers
	shell.material_override = _create_outline_material()
	mesh_instance.add_child(shell)
	_outline_shells[mesh_instance.get_instance_id()] = shell
	return shell

func _get_outline_shell(mesh_instance: MeshInstance3D) -> MeshInstance3D:
	if mesh_instance == null:
		return null
	var existing = _outline_shells.get(mesh_instance.get_instance_id(), null)
	if existing is MeshInstance3D and is_instance_valid(existing):
		return existing
	return null

func _create_outline_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = OBJECT_OUTLINE_SHADER
	material.render_priority = 120
	return material

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
	particles.top_level = true
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-6.0, -6.0, -6.0), Vector3(12.0, 12.0, 12.0))

	var aabb := mesh_instance.mesh.get_aabb()

	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.065
	particle_mesh.height = 0.13
	particle_mesh.material = _make_particle_draw_material(selected_feedback_color, 8.0)
	particles.draw_pass_1 = particle_mesh

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = aabb.size * 0.5 + Vector3.ONE * selected_object_outline_width
	process_material.direction = Vector3.UP
	process_material.spread = 180.0
	process_material.initial_velocity_min = 0.01
	process_material.initial_velocity_max = 0.08
	process_material.gravity = Vector3.ZERO
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
	var aabb := mesh_instance.mesh.get_aabb()
	particles.global_position = mesh_instance.to_global(aabb.position + aabb.size * 0.5)

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
			_outline_particles.erase(mesh_instance.get_instance_id())
			_outline_shells.erase(mesh_instance.get_instance_id())
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
