class_name Interactable
extends Area3D

## Proximity interactable with optional character-specific dialogue.

enum InteractableType {
	HOLD_ACTION,   # proximity: stand near it and the dwell timer runs
	INSPECTION,    # click to walk over; triggers instantly on arrival
	TIMED_ACTION,  # click to walk over; then a dwell/work timer runs on arrival before it triggers
}

@export var dwell_time := 1.5
@export var interaction_radius := 2.0
@export var description := ""
@export var one_shot := false
@export var interaction_enabled := true
@export var interactable_type := InteractableType.HOLD_ACTION
@export var interactable_id := ""
@export var tutorial_label := ""
@export var hover_outline_color := Color.WHITE
@export var selected_feedback_color := Color(1.0, 0.62, 0.12, 1.0)
@export var outline_highlight_radius := 0.0
@export var outline_highlight_height := 0.8
@export var selected_feedback_duration := 2.5
@export var selected_particle_count := 120
@export var selected_particles_enabled := true

## Dialogue key prefix; empty means signal-only.
@export var dialogue_key := ""

## Optional required character id.
@export var required_character := ""

var _player_in_range := false
var _dwell_progress := 0.0
var _used := false

# Gameplay scheduler. When set, a HOLD_ACTION's dwell completion is a scheduled
# event that pauses with gameplay; when null, dwell falls back to the wall clock.
var _scheduler = null
# The dwell is a scheduler-driven mini state machine: armed (waiting) <-> dwelling (timer running).
# Built once the scheduler is injected; the FSM's tag owns the scheduled completion, so leaving
# 'dwelling' (player exits, trigger, disable) cancels it automatically. The enabled/used lifecycle
# stays as the external flag API below (scenes set interaction_enabled directly).
var _dwell_fsm: StateMachine
var _dwell_start_tick := 0.0

# Data-layer binding. When set, GameState owns this interactable's trigger /
# enabled / one-shot state and records triggers for replay; the node is a view.
# When unbound (standalone preview), the node falls back to its @export fields.
var _game_state = null
var data_id := ""

var speed_multiplier := 1.0

## Sequence-owned dialogue target.
var dialogue_box: Node = null
## Active character id.
var active_character := ""

var _progress_ring: MeshInstance3D
var _progress_mat: StandardMaterial3D
var _tutorial_label_3d: Label3D
var _identify_label_3d: Label3D  # data-overlay scan readout of this object's name (hover-to-identify)
var _data_identify := false      # Aster's data overlay is active → hovering reveals the name
var _hover_active := false       # mouse is over this interactable
var _highlight_active := false   # reveal-all overlay (hold SHIFT) is on
var _feedback_emitting := false  # the outline/particle feedback is currently running
var _outline_target              # the object's OutlineSurfaceTarget (outline shader + surface particles)
var _collision_shape: CollisionShape3D
var _selected_particles: GPUParticles3D
var _selected_particle_material: ParticleProcessMaterial
var _feedback_managed := false

signal interacted()
signal outline_hovered(interactable: Node)
signal outline_unhovered(interactable: Node)
signal outline_selected(interactable: Node)
signal interaction_requested(interactable: Node, world_position: Vector3)
## Emitted after resolving dialogue_key.
signal dialogue_triggered(key: String, character: String)

func _ready() -> void:
	if interactable_id != "":
		apply_interactable_spec(interactable_id)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)
	# Match packed-scene physics layers for script-created zones.
	collision_layer = 4 if interaction_enabled else 0
	collision_mask = 2 if interaction_enabled else 0
	input_ray_pickable = true
	_collision_shape = get_node_or_null("CollisionShape3D")
	if _collision_shape != null and _collision_shape.shape != null:
		_collision_shape.shape = _collision_shape.shape.duplicate()
	if _collision_shape != null and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = interaction_radius

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
	_tutorial_label_3d.font_size = 72
	# fixed_size keeps the hint a constant on-screen size: it stays legible far away
	# and never balloons when the follow-camera is close. no_depth_test draws it over
	# the object it labels instead of clipping into the mesh.
	_tutorial_label_3d.fixed_size = true
	_tutorial_label_3d.pixel_size = 0.0006
	_tutorial_label_3d.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_tutorial_label_3d.outline_modulate = Color(0, 0, 0, 0.6)
	_tutorial_label_3d.outline_size = 10
	_tutorial_label_3d.no_depth_test = true
	_tutorial_label_3d.render_priority = 2
	_tutorial_label_3d.position = Vector3(0, 2.2, 0)
	_tutorial_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tutorial_label_3d.visible = false
	add_child(_tutorial_label_3d)
	set_interaction_enabled(interaction_enabled)
	if interaction_enabled:
		call_deferred("_refresh_player_range")


func _process(delta: float) -> void:
	if _used or not interaction_enabled:
		return

	if _tutorial_label_3d and _tutorial_label_3d.visible and _tutorial_label_3d.modulate.a > 0.1:
		var pulse := 0.6 + sin(Time.get_ticks_msec() * 0.003) * 0.25  # @rendering_only: label pulse
		_tutorial_label_3d.modulate.a = pulse

	if _uses_hold_timer() and _player_in_range:
		if _scheduler != null:
			# Scheduler lane: completion is a scheduled event (_on_dwell_complete).
			# The ring is a cosmetic readout of the scheduler clock, nothing more.
			_dwell_progress = clampf(_scheduler.get_current_tick() - _dwell_start_tick, 0.0, dwell_time)
		else:
			_dwell_progress += delta * speed_multiplier
		var t := clampf(_dwell_progress / dwell_time, 0.0, 1.0)
		_progress_mat.albedo_color.a = t * 0.6
		_progress_ring.scale = Vector3.ONE * (0.8 + t * 0.4)

		if _scheduler == null and _dwell_progress >= dwell_time:
			_trigger()
	else:
		if _dwell_progress > 0:
			_dwell_progress = maxf(0, _dwell_progress - delta * 2.0)
			var t := clampf(_dwell_progress / dwell_time, 0.0, 1.0)
			_progress_mat.albedo_color.a = t * 0.3

## Inject the gameplay scheduler so dwell completion is a scheduled event that
## pauses with gameplay. Without it, dwell falls back to the per-frame wall clock.
func set_scheduler(scheduler_ref) -> void:
	_scheduler = scheduler_ref
	if _scheduler != null and _dwell_fsm == null:
		_dwell_fsm = StateMachine.new(_scheduler, "dwell_%d" % get_instance_id())
		_dwell_fsm.add_state("armed")
		_dwell_fsm.add_state("dwelling", _enter_dwelling)
		_dwell_fsm.start("armed")

## Bind this view to a GameState-registered interactable id. Pulls the spec's
## parameters into the node's fields (so all the visual/dwell code is unchanged)
## and routes triggering through the data layer. Optional: an unbound node keeps
## using its @export fields (standalone previews / showcase).
func bind_data(game_state, id: String) -> void:
	_game_state = game_state
	data_id = id
	if _game_state == null or not _game_state.has_interactable(id):
		return
	var spec: Dictionary = _game_state.get_interactable(id)
	interactable_type = InteractableType.HOLD_ACTION if bool(spec.get("requires_hold", true)) else InteractableType.INSPECTION
	dwell_time = float(spec.get("hold_time", dwell_time))
	one_shot = bool(spec.get("one_shot", one_shot))
	required_character = String(spec.get("required_character", required_character))
	if String(spec.get("dialogue_key", "")) != "":
		dialogue_key = String(spec.get("dialogue_key"))
	interaction_radius = float(spec.get("radius", interaction_radius))
	if String(spec.get("tutorial_label", "")) != "":
		tutorial_label = String(spec.get("tutorial_label"))
	interaction_enabled = _game_state.is_interactable_enabled(id)

func _begin_dwell() -> void:
	if _dwell_fsm == null or not _uses_hold_timer() or not _player_in_range:
		return
	if _used or not interaction_enabled:
		return
	# (Re)start the dwell: bounce through 'armed' so re-entering 'dwelling' re-arms the timer even
	# if we were already dwelling (the FSM tag cancels any prior pending completion).
	_dwell_fsm.transition_to("armed")
	_dwell_fsm.transition_to("dwelling")

## 'dwelling' enter hook: reset progress + schedule the completion under the FSM tag.
func _enter_dwelling() -> void:
	_dwell_start_tick = _scheduler.get_current_tick()
	_dwell_progress = 0.0
	_dwell_fsm.schedule(dwell_time, _on_dwell_complete)

func _cancel_dwell() -> void:
	# Back to 'armed' — the FSM cancels the pending completion via its tag.
	if _dwell_fsm != null:
		_dwell_fsm.transition_to("armed")

func _on_dwell_complete() -> void:
	if _player_in_range and not _used and interaction_enabled and _uses_hold_timer():
		_trigger()
		# Non-one-shot interactables re-arm while the player keeps standing in range.
		if not _used and _player_in_range and interaction_enabled:
			_begin_dwell()

func _trigger(play_feedback := true) -> void:
	if _used or not interaction_enabled:
		return
	# When bound, the data layer is the trigger authority (guards the required
	# character + enabled state, records the event for replay, disables one-shots).
	# Unbound, the node guards locally.
	if _game_state != null and data_id != "":
		if not _game_state.trigger_interactable(data_id, active_character):
			return
	elif required_character != "" and active_character != "" and active_character != required_character:
		return

	if one_shot:
		_used = true
	_cancel_dwell()
	_dwell_progress = 0.0
	_progress_mat.albedo_color.a = 0.0
	if one_shot:
		set_interaction_enabled(false)
		outline_unhovered.emit(self)
	if _tutorial_label_3d:
		_tutorial_label_3d.modulate.a = 0.0
	if play_feedback:
		if not _feedback_managed:
			play_selected_feedback()
		outline_selected.emit(self)

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
	if _tutorial_label_3d and interaction_enabled:
		_tutorial_label_3d.visible = true
		_tutorial_label_3d.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_tutorial_label_3d, "modulate:a", 0.9, 0.5)

func hide_tutorial_label() -> void:
	if _tutorial_label_3d:
		var tween := create_tween()
		tween.tween_property(_tutorial_label_3d, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): _tutorial_label_3d.visible = false)

## Reveal-all overlay (hold SHIFT): show this interactable's highlight. Shares the same feedback
## as hover — a hovered object and a revealed one read identically. The interactable is a meshless
## proximity zone that intercepts the hover ray, so the actual visual is its OBJECT's
## OutlineSurfaceTarget (the outline SHADER + particles emitted from the mesh surface), linked via
## set_outline_target(). No more stray footprint ring that ignored the object's shape.
func set_highlight(active: bool) -> void:
	_highlight_active = active
	_refresh_feedback()

## Link the OutlineSurfaceTarget that wraps this interactable's object meshes (set by the
## sequence's _set_room_target_interaction_delegate). Hover / SHIFT then light up THAT — the real
## outline + surface particles — instead of the interactable emitting its own ring.
func set_outline_target(target) -> void:
	_outline_target = target
	if _outline_target != null and is_instance_valid(_outline_target):
		_outline_target.set_highlight(_feedback_emitting)

func _on_body_entered(body: Node3D) -> void:
	if _used or not interaction_enabled:
		return
	if body is CharacterBody3D:
		_player_in_range = true
		_dwell_progress = 0.0
		if _proximity_dwell():  # only HOLD_ACTION auto-dwells on proximity; TIMED_ACTION waits for a click
			_begin_dwell()

func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_in_range = false
		_cancel_dwell()

func _on_mouse_entered() -> void:
	if _used or not interaction_enabled:
		return
	if not _feedback_managed:
		set_hover_feedback(true)
	outline_hovered.emit(self)

func _on_mouse_exited() -> void:
	if not _feedback_managed:
		set_hover_feedback(false)
	outline_unhovered.emit(self)

func _on_input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if _used or not interaction_enabled:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		# RIGHT-click is the interact command (RTS-style). A LEFT-click is NEVER an interaction —
		# it falls through to the player as a plain move/select, so clicking past or grazing an
		# object's pick volume no longer walks the character onto it (the old hijack).
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
			get_viewport().set_input_as_handled()
			interaction_requested.emit(self, global_position)
			outline_selected.emit(self)

func play_selected_feedback() -> void:
	if not selected_particles_enabled:
		return
	_ensure_selected_particles()
	_selected_particles.amount = maxi(1, selected_particle_count)
	_selected_particles.lifetime = maxf(0.1, selected_feedback_duration)
	_selected_particle_material.color = selected_feedback_color
	_set_particle_draw_color(_selected_particles, selected_feedback_color, 8.0)
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
	_selected_particles.visibility_aabb = AABB(Vector3(-6.0, -6.0, -6.0), Vector3(12.0, 12.0, 12.0))

	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.08
	particle_mesh.height = 0.16
	particle_mesh.material = _make_particle_draw_material(selected_feedback_color, 8.0)
	_selected_particles.draw_pass_1 = particle_mesh

	# Trace the interactable's outline (its interaction footprint) instead of a single
	# central blob: a ring band around the radius, raised into a short column so the
	# spread reads as wrapping the object. Mesh-free, so it works in every scene.
	var ring_radius := maxf(0.45, interaction_radius * 0.7)
	var ring_height := maxf(0.6, outline_highlight_height * 1.4)
	_selected_particles.position = Vector3(0.0, ring_height * 0.5, 0.0)
	_selected_particle_material = ParticleProcessMaterial.new()
	_selected_particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_selected_particle_material.emission_ring_axis = Vector3.UP
	_selected_particle_material.emission_ring_radius = ring_radius
	_selected_particle_material.emission_ring_inner_radius = maxf(0.0, ring_radius - 0.3)
	_selected_particle_material.emission_ring_height = ring_height
	_selected_particle_material.direction = Vector3.UP
	_selected_particle_material.spread = 60.0
	_selected_particle_material.initial_velocity_min = 0.05
	_selected_particle_material.initial_velocity_max = 0.18
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

## Hover feedback — driven by the OutlineFeedbackManager (bound interactables) or the bare
## mouse_entered hook. Shows the SAME outline/particle highlight as the reveal overlay, so a
## hovered object and a SHIFT-revealed one read identically.
func set_hover_feedback(active: bool) -> void:
	_hover_active = active
	_refresh_feedback()
	if _data_identify:
		_set_identify_label_visible(active)

## Aster's data overlay (de)activates: when on, hovering this object reveals its name. Toggling off
## hides the readout even if still hovered. Set by the sequence for every interactable.
func set_data_identify(active: bool) -> void:
	_data_identify = active
	if not active:
		_set_identify_label_visible(false)
	elif _hover_active:
		_set_identify_label_visible(true)

func _identify_name() -> String:
	if description != "":
		return description
	if tutorial_label != "" and tutorial_label != "Click":
		return tutorial_label
	return name.replace("_", " ").replace("Zone", "").strip_edges()

func _set_identify_label_visible(should_show: bool) -> void:
	if should_show and (_used or not interaction_enabled or _identify_name() == ""):
		return
	if should_show:
		_ensure_identify_label()
		_identify_label_3d.text = "// %s //" % _identify_name().to_upper()
		_identify_label_3d.visible = true
	elif _identify_label_3d != null:
		_identify_label_3d.visible = false

func _ensure_identify_label() -> void:
	if _identify_label_3d != null:
		return
	_identify_label_3d = Label3D.new()
	_identify_label_3d.name = "IdentifyLabel"
	_identify_label_3d.font_size = 56
	_identify_label_3d.fixed_size = true
	_identify_label_3d.pixel_size = 0.0005
	_identify_label_3d.modulate = Color(0.45, 0.78, 1.0, 0.95)  # Aster data-overlay cyan
	_identify_label_3d.outline_modulate = Color(0.0, 0.05, 0.12, 0.85)
	_identify_label_3d.outline_size = 12
	_identify_label_3d.no_depth_test = true
	_identify_label_3d.render_priority = 3
	_identify_label_3d.position = Vector3(0.0, 1.7, 0.0)
	_identify_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_identify_label_3d.visible = false
	add_child(_identify_label_3d)

## Drive the object's outline+particle highlight while EITHER hover or the reveal overlay wants
## it; stop when neither does. The visual is the linked OutlineSurfaceTarget (outline shader +
## surface-emitted particles). A meshless interactable with no target shows nothing — by design,
## there's no object to outline (and no clustered ring that ignores the shape).
func _refresh_feedback() -> void:
	var want := (_hover_active or _highlight_active) and interaction_enabled and not _used
	if want == _feedback_emitting:
		return
	_feedback_emitting = want
	if _outline_target != null and is_instance_valid(_outline_target):
		_outline_target.set_highlight(want)

func set_interaction_enabled(active: bool) -> void:
	interaction_enabled = active
	# Keep the data layer's enabled flag in sync so trigger guards + range queries
	# stay accurate (no-op + no log when unchanged).
	if _game_state != null and data_id != "" and _game_state.has_interactable(data_id):
		_game_state.set_interactable_enabled(data_id, active)
	monitoring = active
	monitorable = active
	collision_layer = 4 if active else 0
	collision_mask = 2 if active else 0
	input_ray_pickable = active and not _used
	_cancel_dwell()
	_player_in_range = false
	_dwell_progress = 0.0
	if _progress_mat != null:
		_progress_mat.albedo_color.a = 0.0
	if _tutorial_label_3d != null and not active:
		_tutorial_label_3d.visible = false
		_tutorial_label_3d.modulate.a = 0.0
	if not active:
		_set_identify_label_visible(false)  # a disabled object surfaces no scan readout
	# A disabled / consumed interactable stops its highlight even if hover/SHIFT still wants it.
	_refresh_feedback()
	if active:
		call_deferred("_refresh_player_range")

func is_interaction_enabled() -> bool:
	return interaction_enabled

func apply_interactable_spec(spec_id: String) -> void:
	var catalog_script = load("res://scripts/game/objects/interactable_catalog.gd")
	if catalog_script != null:
		catalog_script.apply_spec(self, spec_id)
	if _tutorial_label_3d != null:
		_tutorial_label_3d.text = tutorial_label if tutorial_label != "" else "Click"
	if _collision_shape != null and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = interaction_radius
	if is_inside_tree():
		set_interaction_enabled(interaction_enabled)

func on_interaction_arrived() -> void:
	if _triggers_on_arrival():
		_trigger(false)
	elif _works_on_arrival():
		# Walked over via a click; now run the work/tend timer (the character is here, so it's in range),
		# and _on_dwell_complete fires the actual trigger once dwell_time elapses.
		_player_in_range = true
		_begin_dwell()

func _refresh_player_range() -> void:
	if not interaction_enabled or not monitoring or _used:
		return
	_player_in_range = false
	for body in get_overlapping_bodies():
		if body is CharacterBody3D:
			_player_in_range = true
			break
	if _player_in_range and _proximity_dwell():
		_begin_dwell()

## The dwell/work timer machinery applies (proximity HOLD_ACTION and arrival TIMED_ACTION both use it).
func _uses_hold_timer() -> bool:
	return interactable_type == InteractableType.HOLD_ACTION or interactable_type == InteractableType.TIMED_ACTION

## Auto-begins the dwell when a body enters range — only the proximity type. TIMED_ACTION begins its
## dwell on click-arrival instead (on_interaction_arrived), so it never triggers just by walking past.
func _proximity_dwell() -> bool:
	return interactable_type == InteractableType.HOLD_ACTION

func _triggers_on_arrival() -> bool:
	return interactable_type == InteractableType.INSPECTION

func _works_on_arrival() -> bool:
	return interactable_type == InteractableType.TIMED_ACTION

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

func begin_queued_feedback(_origin: Vector3 = Vector3.ZERO) -> void:
	play_selected_feedback()

func complete_queued_feedback() -> void:
	if _selected_particles != null:
		_clear_particle_emitter(_selected_particles)

func cancel_queued_feedback() -> void:
	complete_queued_feedback()

func get_outline_highlight_radius() -> float:
	return outline_highlight_radius if outline_highlight_radius > 0.0 else interaction_radius

func get_outline_highlight_origin() -> Vector3:
	return global_position + Vector3(0.0, outline_highlight_height, 0.0)

func get_interaction_target_position(_from_position: Vector3 = Vector3.ZERO, _requested_position: Vector3 = Vector3.INF) -> Vector3:
	return global_position

func reset() -> void:
	_used = false
	_player_in_range = false
	_dwell_progress = 0.0
	_progress_mat.albedo_color.a = 0.0
	# Re-arm the data layer too (clear triggered), so a one-shot can fire again.
	if _game_state != null and data_id != "" and _game_state.has_interactable(data_id):
		_game_state.reset_interactable(data_id)
	set_interaction_enabled(true)

func get_dwell_progress() -> float:
	return _dwell_progress / dwell_time if dwell_time > 0 else 0.0

func is_player_in_range() -> bool:
	return _player_in_range
