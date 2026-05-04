class_name Interactable
extends Area3D

## Proximity-based interactable. Stand near it and it activates.
## Supports character-specific dialogue: set dialogue_key and the
## interactable resolves the key with a character suffix automatically.
##
## Example: dialogue_key = "junction.food", active character = "aster"
##   → looks up "junction.food.aster", falls back to "junction.food"
##
## For interactions that need custom logic beyond dialogue, connect
## the interacted signal.

@export var dwell_time := 1.5
@export var interaction_radius := 2.0
@export var description := ""
@export var one_shot := false
@export var tutorial_label := ""
@export var show_interaction_zone := true
@export var interaction_zone_color := Color(0.35, 0.75, 0.55, 0.16)
@export var hover_outline_color := Color.WHITE
@export var selected_feedback_color := Color(1.0, 0.62, 0.12, 1.0)
@export var outline_highlight_radius := 0.0
@export var outline_highlight_height := 0.8
@export var selected_feedback_duration := 0.7
@export var selected_particle_count := 24
@export var selected_particles_enabled := true

## Dialogue key prefix. On interaction, resolves character-specific variant.
## Leave empty for no automatic dialogue (signal-only interaction).
@export var dialogue_key := ""

## If set, only this character can trigger the interaction.
## Empty = any character.
@export var required_character := ""

var _player_in_range := false
var _dwell_progress := 0.0
var _used := false

var speed_multiplier := 1.0

## Set by the sequence to route dialogue. If null, dialogue_key is ignored.
var dialogue_box: Node = null
## Set by the sequence to identify which character is interacting.
var active_character := ""

var _progress_ring: MeshInstance3D
var _progress_mat: StandardMaterial3D
var _zone_marker: MeshInstance3D
var _zone_mat: StandardMaterial3D
var _tutorial_label_3d: Label3D
var _collision_shape: CollisionShape3D
var _selected_particles: GPUParticles3D
var _selected_particle_material: ParticleProcessMaterial

signal interacted()
signal outline_hovered(interactable: Node)
signal outline_unhovered(interactable: Node)
signal outline_selected(interactable: Node)
## Emitted with the resolved dialogue key when dialogue_key is set
signal dialogue_triggered(key: String, character: String)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)
	# Keep script-created interactables aligned with the packed scene's
	# physics contract: interactables detect player bodies on layer 2.
	collision_layer = 4
	collision_mask = 2
	input_ray_pickable = true
	_collision_shape = get_node_or_null("CollisionShape3D")
	if _collision_shape != null and _collision_shape.shape != null:
		_collision_shape.shape = _collision_shape.shape.duplicate()
	if _collision_shape != null and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = interaction_radius

	_build_zone_marker()

	_progress_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.05, interaction_radius - 0.18)
	torus.outer_radius = interaction_radius
	torus.rings = 24
	torus.ring_segments = 12
	_progress_ring.mesh = torus
	_progress_mat = StandardMaterial3D.new()
	_progress_mat.albedo_color = Color(0.4, 0.7, 0.5, 0.0)
	_progress_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_progress_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_progress_ring.material_override = _progress_mat
	_progress_ring.position = Vector3(0, 0.05, 0)
	_progress_ring.rotation.x = -PI / 2.0
	add_child(_progress_ring)

	_tutorial_label_3d = Label3D.new()
	_tutorial_label_3d.text = tutorial_label if tutorial_label != "" else "Click"
	_tutorial_label_3d.font_size = 48
	_tutorial_label_3d.pixel_size = 0.012
	_tutorial_label_3d.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_tutorial_label_3d.outline_modulate = Color(0, 0, 0, 0.5)
	_tutorial_label_3d.outline_size = 8
	_tutorial_label_3d.position = Vector3(0, 2.2, 0)
	_tutorial_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tutorial_label_3d.visible = false
	add_child(_tutorial_label_3d)

func _build_zone_marker() -> void:
	_zone_marker = MeshInstance3D.new()
	_zone_marker.name = "InteractionZoneMarker"
	_zone_marker.visible = show_interaction_zone
	var disc := CylinderMesh.new()
	disc.top_radius = interaction_radius
	disc.bottom_radius = interaction_radius
	disc.height = 0.012
	disc.radial_segments = 64
	_zone_marker.mesh = disc
	_zone_mat = StandardMaterial3D.new()
	_zone_mat.albedo_color = interaction_zone_color
	_zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_zone_marker.material_override = _zone_mat
	_zone_marker.position = Vector3(0, 0.018, 0)
	add_child(_zone_marker)

func _process(delta: float) -> void:
	if _used:
		return

	if _tutorial_label_3d and _tutorial_label_3d.visible and _tutorial_label_3d.modulate.a > 0.1:
		var pulse := 0.6 + sin(Time.get_ticks_msec() * 0.003) * 0.25  # @rendering_only — tutorial label pulse
		_tutorial_label_3d.modulate.a = pulse

	if _player_in_range:
		_dwell_progress += delta * speed_multiplier
		var t := clampf(_dwell_progress / dwell_time, 0.0, 1.0)
		_progress_mat.albedo_color.a = t * 0.6
		_progress_ring.scale = Vector3.ONE * (0.8 + t * 0.4)

		if _dwell_progress >= dwell_time:
			_trigger()
	else:
		if _dwell_progress > 0:
			_dwell_progress = maxf(0, _dwell_progress - delta * 2.0)
			var t := clampf(_dwell_progress / dwell_time, 0.0, 1.0)
			_progress_mat.albedo_color.a = t * 0.3

func _trigger() -> void:
	# Character gate
	if required_character != "" and active_character != "" and active_character != required_character:
		return

	if one_shot:
		_used = true
	_dwell_progress = 0.0
	_progress_mat.albedo_color.a = 0.0
	if one_shot and _zone_marker:
		_zone_marker.visible = false
	if one_shot:
		input_ray_pickable = false
		outline_unhovered.emit(self)
	if _tutorial_label_3d:
		_tutorial_label_3d.modulate.a = 0.0
	play_selected_feedback()
	outline_selected.emit(self)

	# Resolve dialogue
	if dialogue_key != "":
		var resolved := _resolve_dialogue_key()
		if dialogue_box and resolved != "":
			DialogueData.say_to(dialogue_box, resolved)
		dialogue_triggered.emit(resolved, active_character)

	interacted.emit()

func _resolve_dialogue_key() -> String:
	if dialogue_key == "":
		return ""
	if active_character != "":
		var char_key := dialogue_key + "." + active_character
		var line := DialogueData.get_line(char_key)
		if not line.text.begins_with("[MISSING:"):
			return char_key
	var line := DialogueData.get_line(dialogue_key)
	if not line.text.begins_with("[MISSING:"):
		return dialogue_key
	return ""

func show_tutorial_label() -> void:
	if _tutorial_label_3d:
		_tutorial_label_3d.visible = true
		_tutorial_label_3d.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_tutorial_label_3d, "modulate:a", 0.9, 0.5)

func hide_tutorial_label() -> void:
	if _tutorial_label_3d:
		var tween := create_tween()
		tween.tween_property(_tutorial_label_3d, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): _tutorial_label_3d.visible = false)

func _on_body_entered(body: Node3D) -> void:
	if _used:
		return
	if body is CharacterBody3D:
		_player_in_range = true
		_dwell_progress = 0.0

func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_in_range = false

func _on_mouse_entered() -> void:
	if _used:
		return
	outline_hovered.emit(self)

func _on_mouse_exited() -> void:
	outline_unhovered.emit(self)

func _on_input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if _used:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			get_viewport().set_input_as_handled()
			play_selected_feedback()
			outline_selected.emit(self)

func play_selected_feedback() -> void:
	if not selected_particles_enabled:
		return
	_ensure_selected_particles()
	_selected_particles.amount = maxi(1, selected_particle_count)
	_selected_particles.lifetime = maxf(0.1, selected_feedback_duration)
	_selected_particle_material.color = selected_feedback_color
	_selected_particles.restart()
	_selected_particles.emitting = true

func _ensure_selected_particles() -> void:
	if _selected_particles != null:
		return
	_selected_particles = GPUParticles3D.new()
	_selected_particles.name = "SelectedParticles"
	_selected_particles.amount = maxi(1, selected_particle_count)
	_selected_particles.lifetime = maxf(0.1, selected_feedback_duration)
	_selected_particles.one_shot = true
	_selected_particles.explosiveness = 1.0
	_selected_particles.emitting = false
	_selected_particles.position = Vector3(0.0, outline_highlight_height, 0.0)

	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.035
	particle_mesh.height = 0.07
	_selected_particles.draw_pass_1 = particle_mesh

	_selected_particle_material = ParticleProcessMaterial.new()
	_selected_particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_selected_particle_material.emission_sphere_radius = maxf(0.25, interaction_radius * 0.3)
	_selected_particle_material.direction = Vector3.UP
	_selected_particle_material.spread = 70.0
	_selected_particle_material.initial_velocity_min = 0.8
	_selected_particle_material.initial_velocity_max = 2.4
	_selected_particle_material.gravity = Vector3(0.0, -2.0, 0.0)
	_selected_particle_material.scale_min = 0.025
	_selected_particle_material.scale_max = 0.08
	_selected_particle_material.color = selected_feedback_color
	_selected_particles.process_material = _selected_particle_material
	add_child(_selected_particles)

func get_outline_highlight_radius() -> float:
	return outline_highlight_radius if outline_highlight_radius > 0.0 else interaction_radius

func get_outline_highlight_origin() -> Vector3:
	return global_position + Vector3(0.0, outline_highlight_height, 0.0)

func reset() -> void:
	_used = false
	_player_in_range = false
	_dwell_progress = 0.0
	_progress_mat.albedo_color.a = 0.0
	input_ray_pickable = true

func get_dwell_progress() -> float:
	return _dwell_progress / dwell_time if dwell_time > 0 else 0.0

func is_player_in_range() -> bool:
	return _player_in_range
