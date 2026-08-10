class_name Interactable
extends Area3D

## Proximity interactable with optional character-specific dialogue.

# ACTIVATION GRAMMAR — the MAJORITY of level interactables must be CLICK-GATED. Picking the type:
#   INSPECTION   — click to walk over; fires INSTANTLY on arrival. The DEFAULT for a discrete action
#                  (read / take / override / fire a lure / flip a switch).
#   TIMED_ACTION — click to walk over; then a work/hold beat runs on arrival before it fires. For an action
#                  with a real dwell (salvage, tend, survey).
#   HOLD_ACTION  — PROXIMITY: stand near it and the dwell auto-runs, NO click. RESERVED for the rare,
#                  justified proximity action (rest/bed-down points, work-stations). Do NOT use it for a
#                  discrete object action — that is the "why did this fire when I walked past?" bug.
# SceneChunk._add_interactable DEFAULTS to INSPECTION, so a new level that omits the type ships click-gated,
# never accidental proximity; HOLD_ACTION must be opted into explicitly. Every VISIBLE interactable must also
# be wired to an OutlineSurfaceTarget (shared outline+glow shaders) — use _add_object_interactable /
# _outline_interactable_child for procedural meshes. The --test-chunk-interactable-outlines guard enforces
# both invariants per interactable across representative chunks (with a small allowlist for the proximity ones).
enum InteractableType {
	HOLD_ACTION,   # proximity: stand near it and the dwell timer runs (opt-in; rest points / work-stations)
	INSPECTION,    # click to walk over; triggers instantly on arrival (the default for discrete actions)
	TIMED_ACTION,  # click to walk over; then a dwell/work timer runs on arrival before it triggers
}

@export var dwell_time := 1.5
@export var interaction_radius := 2.0
@export var description := ""
## Concrete, pre-commit consequence shown beside the cursor verb. Keep this as a
## prediction the runtime can actually honor, not another object name.
@export_multiline var consequence_preview := ""
@export var one_shot := false
@export var interaction_enabled := true:
	set(value):
		interaction_enabled = value
		_sync_outline_target_command_availability()
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
## Cosmetic juice on click/trigger (InteractableJuice): "prop" = squash-and-settle
## on trigger + a click-commit nudge; "plant" = the same plus an organic rustle on
## hover and trigger; "none" = still. Purely visual, never a scheduler tick.
@export_enum("prop", "plant", "none") var juice_profile: String = "prop"

## Dialogue key prefix; empty means signal-only.
@export var dialogue_key := ""

## Optional required character id.
@export var required_character := ""

var _player_in_range := false
var _dwell_progress := 0.0
var _used := false:
	set(value):
		_used = value
		_sync_outline_target_command_availability()

# Gameplay scheduler. When set, a HOLD_ACTION's dwell completion is a scheduled
# event that pauses with gameplay; when null, dwell falls back to the wall clock.
var _scheduler = null
# The dwell is a scheduler-driven mini state machine: armed (waiting) <-> dwelling (timer running).
# Built once the scheduler is injected; the FSM's tag owns the scheduled completion, so leaving
# 'dwelling' (player exits, trigger, disable) cancels it automatically. The enabled/used lifecycle
# stays as the external flag API below (scenes set interaction_enabled directly).
var _dwell_fsm: StateMachine
var _dwell_start_tick := 0.0
## How many times the hold has been (re)armed. A hold that restarts keeps cancelling its own
## completion, so a stalled dwell and a perpetually-restarted one are told apart by this count.
var _dwell_restarts := 0
# Standalone previews can omit the gameplay scheduler. Keep an explicit fallback
# state so their wall-clock dwell has the same armed/dwelling lifecycle as the FSM.
var _fallback_dwelling := false

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
## Immutable owner of the pointer command while `interaction_requested` is
## synchronously being delivered. `active_character` is also used by the
## servicing interaction and may change to a required party member; listeners
## must never use that mutable field to decide whether the same click is theirs.
var _interaction_request_owner := ""

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
var _movement_gs           # GameState movement authority: dwell arms on arrival, cancels on move
var _dwell_char_id := ""   # who armed the dwell (char_id of the body in range)
var _dwell_pending := false  # in range but still walking — the dwell starts on arrival
## Save/load authority for committed work. EventScheduler does not serialize Callables, so a local
## `dwelling` flag cannot survive its callback heap being cleared during load. Bound interactions
## publish their actor, phase, and absolute completion tick into GameState.world_state; this node,
## its StateMachine, and the progress ring are presenters rebuilt from that record.
const DWELL_AUTHORITY_VERSION := 1
const DWELL_AUTHORITY_PREFIX := "runtime:interactable_dwell:"
var _dwell_deadline := -1.0
var _restoring_dwell_authority := false
var _dwell_authority_initialized := false
var _owner_used_override: Variant = null
var _owner_enabled_override: Variant = null
## Optional scenario-owned preflight. The callable must be a pure query with signature
## `(interactable, active_character) -> bool`: it runs before GameState records a trigger and before
## this presenter mutates one-shot, dwell, feedback, or dialogue state. An invalid callable preserves
## the legacy/default behavior.
var _pre_trigger_validator := Callable()
## Optional click-route preflight. Unlike `_pre_trigger_validator`, this query
## runs before any movement is committed. It may only inspect current authority
## and returns a plain result dictionary; presentation is a separate callable so
## observation never changes selection, movement, inventory, or puzzle state.
## Query signature: `(interactable, active_character) -> Dictionary`.
## Presenter signature: `(interactable, active_character, result) -> void`.
var _interaction_route_preflight := Callable()
var _interaction_route_refusal_presenter := Callable()

signal interacted()
## The authoritative trigger rejected this interaction. `required_character` is populated for a
## character mismatch and empty for another preflight/authority refusal. The linked object surface
## always consumes this signal so a rejected player command gets an exact red target result instead
## of failing silently.
signal interaction_rejected(interactable: Node, required_character: String)
signal outline_hovered(interactable: Node)
signal outline_unhovered(interactable: Node)
signal outline_selected(interactable: Node)
signal interaction_requested(interactable: Node, world_position: Vector3)
## Emitted after resolving dialogue_key.
signal dialogue_triggered(key: String, character: String)

func _ready() -> void:
	if interactable_id != "":
		apply_interactable_spec(interactable_id)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
	# Match packed-scene physics layers for script-created zones.
	collision_layer = 4 if interaction_enabled else 0
	collision_mask = 2 if interaction_enabled else 0
	input_ray_pickable = is_pointer_command_available()
	_collision_shape = get_node_or_null("CollisionShape3D")
	if _collision_shape != null and _collision_shape.shape != null:
		_collision_shape.shape = _collision_shape.shape.duplicate()
	if _collision_shape != null and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = interaction_radius

	_progress_ring = MeshInstance3D.new()
	# Named so mesh collectors can EXCLUDE it: the ring is a dwell-progress READOUT spanning the whole
	# interaction radius — never object geometry. An auto-outline that wraps it inflates the pick body
	# to the zone size and swallows neighbouring interactables' hover rays (the hub-wheel bug).
	_progress_ring.name = "InteractableProgressRing"
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
	_tutorial_label_3d.text = InputLabels.expand(tutorial_label) if tutorial_label != "" else InputLabels.action_label("command")
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
	var perf_started := PerformanceTrace.begin()

	if _tutorial_label_3d and _tutorial_label_3d.visible and _tutorial_label_3d.modulate.a > 0.1:
		var pulse := 0.6 + sin(Time.get_ticks_msec() * 0.003) * 0.25  # @rendering_only: label pulse
		_tutorial_label_3d.modulate.a = pulse

	if _uses_hold_timer() and _player_in_range and _is_dwelling():
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
			_on_dwell_complete()
	else:
		if _dwell_progress > 0:
			_dwell_progress = maxf(0, _dwell_progress - delta * 2.0)
			var t := clampf(_dwell_progress / dwell_time, 0.0, 1.0)
			_progress_mat.albedo_color.a = t * 0.3

	# Self-gate: with no label pulsing, no dwell running, and no ring decaying, there is nothing
	# per-frame to do — stop processing until a state change re-enables it (a scene full of idle
	# interactables would otherwise pay a per-frame _process cost for nothing).
	if not _frame_work_pending():
		set_process(false)
	PerformanceTrace.end(&"update", &"interactable.process", perf_started, interactable_id, 1)

func _frame_work_pending() -> bool:
	if _tutorial_label_3d != null and _tutorial_label_3d.visible:
		return true
	if _uses_hold_timer() and _is_dwelling():
		return true
	return _dwell_progress > 0.0

## Inject the gameplay scheduler so dwell completion is a scheduled event that
## pauses with gameplay. Without it, dwell falls back to the per-frame wall clock.
func set_scheduler(scheduler_ref) -> void:
	_scheduler = scheduler_ref
	if _scheduler == null:
		return
	if _dwell_fsm == null:
		_dwell_fsm = StateMachine.new(_scheduler, "dwell_%d" % get_instance_id())
		_dwell_fsm.add_state("armed")
		_dwell_fsm.add_state("dwelling", _enter_dwelling)
		_dwell_fsm.start("armed")
		return
	# The wiring pass runs more than once across a scene's life, and the last one is authoritative.
	# An FSM left pointing at the earlier clock arms its completion where nothing advances: the field
	# would name one scheduler while the hold timer waited on another, and the dwell would sit in
	# `dwelling` forever with every outward sign reading healthy.
	_dwell_fsm.set_scheduler(_scheduler)

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
	var legacy_type := InteractableType.HOLD_ACTION \
		if bool(spec.get("requires_hold", true)) else InteractableType.INSPECTION
	interactable_type = int(spec.get("interactable_type", legacy_type))
	if interactable_type < InteractableType.HOLD_ACTION \
			or interactable_type > InteractableType.TIMED_ACTION:
		interactable_type = legacy_type
	dwell_time = float(spec.get("hold_time", dwell_time))
	one_shot = bool(spec.get("one_shot", one_shot))
	required_character = String(spec.get("required_character", required_character))
	if String(spec.get("dialogue_key", "")) != "":
		dialogue_key = String(spec.get("dialogue_key"))
	interaction_radius = float(spec.get("radius", interaction_radius))
	if String(spec.get("tutorial_label", "")) != "":
		tutorial_label = String(spec.get("tutorial_label"))
	interaction_enabled = _game_state.is_interactable_enabled(id)

## Stable key for an in-flight interaction commitment. Data-first objects use their registered ID;
## older directly-instantiated production objects fall back to their stable scene-tree path once a
## movement GameState has been injected. Standalone previews have no authority and stay ephemeral.
func _dwell_authority_key() -> String:
	var stable_id := data_id
	if stable_id == "" and is_inside_tree():
		stable_id = str(get_path())
	return DWELL_AUTHORITY_PREFIX + stable_id if stable_id != "" else ""

func _dwell_authority_game_state():
	if _game_state != null:
		return _game_state
	return _movement_gs

func _publish_dwell_authority(phase: String) -> void:
	if _restoring_dwell_authority:
		return
	# Scene construction calls set_interaction_enabled(), which cancels an otherwise empty FSM. That
	# default must never overwrite a restored in-flight record before the post-load attachment hook.
	if not _dwell_authority_initialized and phase == "idle":
		return
	var authority = _dwell_authority_game_state()
	var key := _dwell_authority_key()
	if authority == null or key == "" or not authority.has_method("set_world_state"):
		return
	authority.set_world_state(key, {
		"version": DWELL_AUTHORITY_VERSION,
		"phase": phase,
		"actor": _dwell_char_id,
		"deadline": _dwell_deadline,
		# TIMED_ACTION arrival creates a logical range without a physics overlap event.
		"range_active": _player_in_range,
	})

func _begin_dwell(arrival_receipt := false) -> void:
	if _restoring_dwell_authority:
		return
	if not _uses_hold_timer() or not _player_in_range:
		return
	if _used or not interaction_enabled:
		return
	_dwell_authority_initialized = true
	# The hold times from STANDING at the object, never from crossing the zone edge mid-walk: a 2-unit
	# radius with a sub-second dwell would otherwise be mostly elapsed before the character even stops
	# (and then fire while they walk away). While the dwelling character is moving, the dwell is PENDING
	# and arms on the data-layer arrival; starting a new move cancels it (see _on_authority_*).
	if not arrival_receipt and _movement_gs != null and _dwell_char_id != "" \
			and _movement_gs.is_moving(_dwell_char_id):
		_dwell_pending = true
		_dwell_deadline = -1.0
		_publish_dwell_authority("pending")
		return
	_dwell_pending = false
	set_process(true)
	if _dwell_fsm == null:
		_fallback_dwelling = true
		_dwell_progress = 0.0
		return
	# (Re)start the dwell: bounce through 'armed' so re-entering 'dwelling' re-arms the timer even
	# if we were already dwelling (the FSM tag cancels any prior pending completion).
	_dwell_fsm.transition_to("armed")
	_dwell_fsm.transition_to("dwelling")

## 'dwelling' enter hook: reset progress + schedule the completion under the FSM tag.
func _enter_dwelling() -> void:
	_dwell_restarts += 1
	_dwell_start_tick = _scheduler.get_current_tick()
	_dwell_deadline = _dwell_start_tick + dwell_time
	_dwell_progress = 0.0
	_publish_dwell_authority("dwelling")
	_dwell_fsm.schedule(dwell_time, _on_dwell_complete)

func _cancel_dwell() -> void:
	_fallback_dwelling = false
	# Back to 'armed' — the FSM cancels the pending completion via its tag.
	if _dwell_fsm != null:
		_dwell_fsm.transition_to("armed")
	_dwell_deadline = -1.0
	_publish_dwell_authority("idle")

## Wire the GameState whose movement events anchor the hold timer (injected by the sequence alongside
## the scheduler). With no authority the dwell keeps the legacy edge-triggered behavior (standalone use).
func set_movement_authority(game_state) -> void:
	if _movement_gs == game_state or game_state == null:
		return
	_movement_gs = game_state
	if _movement_gs.has_signal("character_arrived"):
		_movement_gs.character_arrived.connect(_on_authority_arrived)
	if _movement_gs.has_signal("movement_started"):
		_movement_gs.movement_started.connect(_on_authority_movement_started)

## Reattach this presenter after GameState has been replaced from a save. Never infer a new outcome:
## mirror the restored registry, then re-arm exactly the remaining portion of its authoritative dwell.
func on_game_state_snapshot_restored() -> void:
	var authority = _dwell_authority_game_state()
	if authority == null:
		return
	_restoring_dwell_authority = true
	# TutorialSequence cleared the callback heap before deserializing. Remove the stale local claim
	# without writing it back over the freshly restored world-state record.
	if _dwell_fsm != null:
		_dwell_fsm.cancel_pending()
		_dwell_fsm.force_current("armed")
	_fallback_dwelling = false
	_dwell_pending = false
	_dwell_deadline = -1.0
	_dwell_progress = 0.0
	_dwell_char_id = ""
	_player_in_range = false

	# One-shot usage and enablement live in the serialized interactable registry. This retracts a
	# future use when loading an earlier snapshot and keeps a saved completion spent after loading it.
	if _game_state != null and data_id != "" and _game_state.has_interactable(data_id):
		var spec: Dictionary = _game_state.get_interactable(data_id)
		_used = bool(spec.get("one_shot", false)) and bool(spec.get("triggered", false))
		set_interaction_enabled(_game_state.is_interactable_enabled(data_id))
	# A staged object such as InfrastructureOperation or an exit shelter owns whether this control is
	# spent. Its restore hook runs before descendants in the production presenter walk; retain that
	# explicit phase projection instead of letting the generic registry infer a second truth.
	if _owner_used_override is bool and _owner_enabled_override is bool:
		_used = bool(_owner_used_override)
		set_interaction_enabled(bool(_owner_enabled_override))

	var key := _dwell_authority_key()
	var saved: Variant = authority.get_world_state(key, {}) if key != "" \
			and authority.has_method("get_world_state") else {}
	var restored_phase := "idle"
	if saved is Dictionary and int(saved.get("version", 0)) == DWELL_AUTHORITY_VERSION:
		restored_phase = str(saved.get("phase", "idle"))
		_dwell_char_id = str(saved.get("actor", ""))
		_player_in_range = bool(saved.get("range_active", false))
		if restored_phase == "pending" and not _used and interaction_enabled:
			_dwell_pending = true
			# Restored ordinary movement emits character_arrived. If the snapshot caught the actor
			# already parked at the boundary, resume on the next idle turn instead of losing the work.
			if _movement_gs == null or _dwell_char_id == "" \
					or not _movement_gs.is_moving(_dwell_char_id):
				call_deferred("_resume_restored_pending_dwell")
		elif restored_phase == "dwelling" and not _used and interaction_enabled and _scheduler != null:
			_dwell_deadline = float(saved.get("deadline", _scheduler.get_current_tick()))
			_dwell_start_tick = _dwell_deadline - dwell_time
			_dwell_progress = clampf(
				_scheduler.get_current_tick() - _dwell_start_tick, 0.0, dwell_time)
			if _dwell_fsm == null:
				set_scheduler(_scheduler)
			_dwell_fsm.force_current("dwelling")
			_dwell_fsm.schedule(
				maxf(0.000001, _dwell_deadline - _scheduler.get_current_tick()),
				_on_dwell_complete)
			set_process(true)
	_restoring_dwell_authority = false
	_dwell_authority_initialized = true
	_refresh_feedback()
	if restored_phase == "idle" and interaction_enabled and not _used:
		call_deferred("_refresh_player_range")

func _resume_restored_pending_dwell() -> void:
	if not _dwell_pending or _used or not interaction_enabled:
		return
	_begin_dwell()

## The dwelling character stopped: a pending (walked-in) hold starts NOW — timed from standing still.
func _on_authority_arrived(id: String) -> void:
	if id != _dwell_char_id or not _player_in_range or _used or not interaction_enabled:
		return
	if _dwell_pending and _proximity_dwell():
		_begin_dwell()

## The dwelling character started moving again: the hold is broken (still in range → re-arms on arrival).
func _on_authority_movement_started(id: String) -> void:
	if id != _dwell_char_id:
		return
	if _is_dwelling():
		_cancel_dwell()
		_dwell_pending = _player_in_range and _proximity_dwell()
		if _dwell_pending:
			_publish_dwell_authority("pending")

func _is_dwelling() -> bool:
	if _dwell_fsm != null:
		return _dwell_fsm.current() == "dwelling"
	return _fallback_dwelling

func _on_dwell_complete() -> void:
	var accepted := false
	if _player_in_range and not _used and interaction_enabled and _uses_hold_timer():
		# A TIMED_ACTION belongs to the body that arrived, not whichever portrait happens to be active
		# when its work ring finishes. HOLD_ACTION already records this from body_entered; click-arrival
		# records it below.
		if _dwell_char_id != "":
			active_character = _dwell_char_id
		accepted = _trigger()
		# Non-one-shot proximity holds re-arm while the player keeps standing in range — verified against
		# REAL overlapping bodies, not the sticky flag. on_interaction_arrived sets _player_in_range from
		# a DATA-layer arrival (no body event ever clears it), so re-arming on the flag alone made a
		# non-one-shot TIMED_ACTION re-tend itself forever after the character had left (The Watched
		# Gap's flure kept re-firing, endlessly yo-yoing the lured sentry).
		if accepted and not _used and interaction_enabled and _proximity_dwell():
			_refresh_player_range()
			if _player_in_range and not _is_dwelling():
				_begin_dwell()
	# The scheduled completion was consumed even when its range/authority guard rejected the action.
	# Never leave the FSM claiming it is dwelling with no completion event behind it; a TIMED_ACTION
	# can be clicked again, while a proximity HOLD_ACTION will re-arm on its next range transition.
	if not accepted and _is_dwelling():
		_cancel_dwell()

func _trigger(play_feedback := true) -> bool:
	if _used or not interaction_enabled:
		return false
	if _pre_trigger_validator.is_valid() \
			and not bool(_pre_trigger_validator.call(self, active_character)):
		# Scenario preflight is an authoritative refusal, not a silent drop: the
		# player reached and attempted the visible object, so the routed click must
		# still surface a target-specific result.
		interaction_rejected.emit(self, required_character)
		return false
	# When bound, the data layer is the trigger authority (guards the required
	# character + enabled state, records the event for replay, disables one-shots).
	# Unbound, the node guards locally.
	if _game_state != null and data_id != "":
		if not _game_state.trigger_interactable(data_id, active_character):
			# Not a silent no-op when the cause is the wrong character: say who is needed.
			if required_character != "" and active_character != "" and active_character != required_character:
				interaction_rejected.emit(self, required_character)
			return false
	elif required_character != "" and active_character != "" and active_character != required_character:
		interaction_rejected.emit(self, required_character)
		return false

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
		outline_selected.emit(self)
		_play_trigger_juice()

	if dialogue_key != "":
		var resolved := _resolve_dialogue_key()
		if dialogue_box and resolved != "":
			DialogueData.say_to(dialogue_box, resolved)
		dialogue_triggered.emit(resolved, active_character)

	interacted.emit()
	return true


func set_pre_trigger_validator(validator: Callable) -> void:
	_pre_trigger_validator = validator


## Install a read-only route gate plus its presentation-only refusal handler.
## Invalid callables preserve the default open route contract.
func set_interaction_route_preflight(
		query: Callable, refusal_presenter := Callable()
	) -> void:
	_interaction_route_preflight = query
	_interaction_route_refusal_presenter = refusal_presenter


## Read-only result consumed by CharacterInteractionController before it asks
## GameState to move anybody. A malformed query fails closed with an explicit
## player-facing reason instead of degrading to an approximate position move.
func get_interaction_route_preflight(character_id: String) -> Dictionary:
	if not _interaction_route_preflight.is_valid():
		return {"accepted": true, "code": ""}
	var result_v: Variant = _interaction_route_preflight.call(self, character_id)
	if not (result_v is Dictionary):
		return {
			"accepted": false,
			"code": "invalid_route_preflight",
			"message": "That object's route contract is unavailable.",
			"cue": "RESOLVE FIRST // ROUTE CONTRACT UNAVAILABLE",
		}
	var result := (result_v as Dictionary).duplicate(true)
	if not result.has("accepted"):
		result["accepted"] = false
	if not result.has("code"):
		result["code"] = "" if bool(result.get("accepted", false)) \
			else "route_preflight_refused"
	return result


## Scenario presentation is deliberately invoked only after a real click has
## been refused. CharacterInteractionController owns the exact clicked-surface
## red pulse; keeping that receipt there prevents a delegate's stale/missing
## outline link from losing the player's source-token result.
func present_interaction_route_refusal(
		character_id: String, result: Dictionary
	) -> void:
	if _interaction_route_refusal_presenter.is_valid():
		_interaction_route_refusal_presenter.call(
			self, character_id, result.duplicate(true))

## The meshes juice animates: the object's registered outline geometry — the
## same meshes the hover mask renders, so the outline squashes with the body.
func _juice_meshes() -> Array:
	if _outline_target != null and is_instance_valid(_outline_target) \
			and _outline_target.has_method("get_highlight_meshes"):
		return _outline_target.call("get_highlight_meshes")
	return []

func _play_trigger_juice() -> void:
	match juice_profile:
		"plant":
			# One beat per node (kill-and-replace) — the strong rustle IS the
			# plant's trigger acknowledgement; a punch would just be killed by it.
			InteractableJuice.rustle(_juice_meshes(), 0.12, 0.7)
			InteractableJuice.tap(35)
		"prop":
			InteractableJuice.punch(_juice_meshes(), 0.14, 0.34)
			InteractableJuice.tap(35)

## Abort a click-gated/timed action because its owning scenario is resetting. This is distinct
## from reset(): it retracts the scheduled dwell without changing one-shot usage or enablement,
## so checkpoint systems can preserve completed work while preventing an in-flight callback from
## firing after the actor has been downed/teleported.
func cancel_pending_interaction() -> void:
	_dwell_pending = false
	_cancel_dwell()
	_dwell_progress = 0.0
	_dwell_char_id = ""
	if _progress_mat != null:
		_progress_mat.albedo_color.a = 0.0
	if _progress_ring != null:
		_progress_ring.scale = Vector3.ONE
	if interactable_type == InteractableType.TIMED_ACTION:
		_player_in_range = false

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

## The one-line ACTION VERB shown above the mouse while this interactable is hovered (the cursor
## verb, drawn by OutlineFeedbackManager). Same text the 3D tutorial hint uses.
func get_action_verb() -> String:
	if _used or not interaction_enabled:
		return ""
	return InputLabels.expand(tutorial_label) if tutorial_label != "" else InputLabels.action_label("command")


## Pair with get_action_verb() as "action -> consequence". Existing authored
## objects fall back to their description; systemic objects should set the
## shorter and mechanically testable consequence_preview explicitly.
func get_action_preview() -> String:
	if _used or not interaction_enabled:
		return ""
	var preview := consequence_preview.strip_edges()
	if preview == "":
		preview = description.strip_edges()
	return InputLabels.expand(preview)

## Presentation seam for an authored WorldCalloutStack3D. The interactable continues to own the
## label's text, pulse, and visibility; a spatial composition may only reserve it a legible row.
func get_tutorial_label_node() -> Label3D:
	return _tutorial_label_3d


## Public presentation-only discovery seam. The meshless interaction Area is
## never enough evidence by itself: expose the linked object's registered,
## visible render geometry, or the tutorial billboard only while that exact
## label is visibly rendered. Policy observers receive opaque tokens later and
## never receive these nodes or authored identities.
func get_player_observation_render_nodes() -> Array[Node3D]:
	var render_nodes: Array[Node3D] = []
	if _outline_target != null and is_instance_valid(_outline_target) \
			and _outline_target.has_method("get_player_observation_render_nodes"):
		var target_nodes_v: Variant = _outline_target.call(
			"get_player_observation_render_nodes"
		)
		if target_nodes_v is Array:
			for node_v in target_nodes_v as Array:
				if node_v is Node3D and is_instance_valid(node_v):
					render_nodes.append(node_v as Node3D)
	if not render_nodes.is_empty():
		return render_nodes
	if _tutorial_label_3d != null \
			and is_instance_valid(_tutorial_label_3d) \
			and _tutorial_label_3d.is_visible_in_tree() \
			and _tutorial_label_3d.modulate.a > 0.01 \
			and not str(_tutorial_label_3d.text).strip_edges().is_empty():
		render_nodes.append(_tutorial_label_3d)
	return render_nodes


## Proxy the target-specific green/red result pulse owned by the linked visible
## object. An unlinked meshless Area has no visual receipt and therefore cannot
## make an automated player call an interaction successful.
func get_player_interaction_presentation() -> Dictionary:
	if _outline_target != null and is_instance_valid(_outline_target) \
			and _outline_target.has_method("get_player_interaction_presentation"):
		var presentation_v: Variant = _outline_target.call(
			"get_player_interaction_presentation"
		)
		if presentation_v is Dictionary:
			return (presentation_v as Dictionary).duplicate(true)
	return {
		"presentation_serial": 0,
		"authority_result": "",
		"result": "",
		"visible": false,
	}


## Optional semantic formation target for a hold-Rally command over this exact
## visible surface. The value is portable data authored by the owning chunk;
## this presenter exposes a defensive copy and never resolves or mutates routes.
func get_rally_formation_region() -> Dictionary:
	if not has_meta("rally_formation_region"):
		return {}
	var region_v: Variant = get_meta("rally_formation_region")
	if not (region_v is Dictionary):
		return {}
	return (region_v as Dictionary).duplicate(true)


## Proxy the real green/red pulse geometry so a presentation observer can
## independently establish that the exact result is currently camera-visible.
func get_player_interaction_presentation_render_nodes() -> Array[Node3D]:
	var render_nodes: Array[Node3D] = []
	if _outline_target == null or not is_instance_valid(_outline_target) \
			or not _outline_target.has_method(
				"get_player_interaction_presentation_render_nodes"):
		return render_nodes
	var target_nodes_v: Variant = _outline_target.call(
		"get_player_interaction_presentation_render_nodes"
	)
	if target_nodes_v is Array:
		for node_v in target_nodes_v as Array:
			if node_v is Node3D and is_instance_valid(node_v):
				render_nodes.append(node_v as Node3D)
	return render_nodes


func get_player_interaction_presentation_screen_candidates(
		camera: Camera3D, viewport: Viewport
	) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	if _outline_target == null or not is_instance_valid(_outline_target) \
			or not _outline_target.has_method(
				"get_player_interaction_presentation_screen_candidates"):
		return candidates
	var target_candidates_v: Variant = _outline_target.call(
		"get_player_interaction_presentation_screen_candidates", camera, viewport
	)
	if target_candidates_v is Array:
		for candidate_v in target_candidates_v as Array:
			if candidate_v is Vector2:
				candidates.append(candidate_v as Vector2)
	return candidates

func show_tutorial_label() -> void:
	set_process(true)  # the label pulse is per-frame work
	if _tutorial_label_3d and interaction_enabled:
		_tutorial_label_3d.visible = true
		_tutorial_label_3d.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_tutorial_label_3d, "modulate:a", 0.9, 0.5)

func hide_tutorial_label() -> void:
	if _tutorial_label_3d:
		var tween := create_tween()
		tween.tween_property(_tutorial_label_3d, "modulate:a", 0.0, 0.3)
		# Do not capture the Label3D itself in a delayed lambda. Dense chunk resets can replace or
		# dispose labels before the tween callback, producing a freed-capture storm during replay.
		tween.tween_callback(_finish_hide_tutorial_label)


func _finish_hide_tutorial_label() -> void:
	if is_instance_valid(_tutorial_label_3d):
		_tutorial_label_3d.visible = false

## Construction-time suppression for dense compositions that already carry authored world labels.
## Unlike hide_tutorial_label(), this does not create a second tween alongside the factory reveal.
func hide_tutorial_label_immediate() -> void:
	if _tutorial_label_3d:
		_tutorial_label_3d.visible = false
		_tutorial_label_3d.modulate.a = 0.0

## Reveal-all overlay (hold SHIFT): show this interactable's highlight. Shares the same feedback
## as hover — a hovered object and a revealed one read identically. The interactable is a meshless
## proximity zone that intercepts the hover ray, so the actual visual is its OBJECT's
## OutlineSurfaceTarget (the outline SHADER + particles emitted from the mesh surface), linked via
## set_outline_target() — a footprint ring of the zone's own would ignore the object's shape.
func set_highlight(active: bool) -> void:
	_highlight_active = active
	_refresh_feedback()

## Link the OutlineSurfaceTarget that wraps this interactable's object meshes (set by the
## sequence's _set_room_target_interaction_delegate). Hover / SHIFT then light up THAT — the real
## outline + surface particles — instead of the interactable emitting its own ring.
func set_outline_target(target) -> void:
	_outline_target = target
	if _outline_target != null and is_instance_valid(_outline_target):
		# Keep the visual/body wrapper and gameplay Area as one canonical command
		# object regardless of which side a procedural builder happened to wire
		# first. Without this reverse link, a ray can hit a fully visible wrapper
		# whose interaction_requested signal was never registered, while the linked
		# Interactable that can actually trigger remains idle.
		if _outline_target.has_method("set_interaction_delegate"):
			_outline_target.call("set_interaction_delegate", self)
		_sync_outline_target_command_availability()
		_outline_target.set_highlight(_feedback_emitting)
	if not interacted.is_connected(_on_visual_interaction_succeeded):
		interacted.connect(_on_visual_interaction_succeeded)
	if not interaction_rejected.is_connected(_on_visual_interaction_rejected):
		interaction_rejected.connect(_on_visual_interaction_rejected)


func _on_visual_interaction_succeeded() -> void:
	play_interaction_result(true)


func _on_visual_interaction_rejected(_interactable: Node, _required_character: String) -> void:
	play_interaction_result(false)


## Public presentation surface used when the routed approach itself is authoritatively refused
## before this object's trigger can run. It forwards to the same linked mesh pulse as ordinary
## trigger success/rejection and never changes gameplay state.
func play_interaction_result(succeeded: bool) -> void:
	if _outline_target != null and is_instance_valid(_outline_target) \
			and _outline_target.has_method("play_interaction_result"):
		_outline_target.call("play_interaction_result", succeeded)

func _on_body_entered(body: Node3D) -> void:
	if _used or not interaction_enabled:
		return
	if body is CharacterBody3D:
		set_process(true)  # dwell ring / label work resumes
		_player_in_range = true
		# The first body owns the whole dwell, including its still-walking pending state. A bystander
		# crossing later must neither steal the actor nor restart the timer; exit hands ownership off.
		if not _is_dwelling() and not _dwell_pending:
			_dwell_char_id = str(body.get("char_id")) if body.get("char_id") != null else ""
			_dwell_progress = 0.0
			if _proximity_dwell():  # only HOLD_ACTION auto-dwells on proximity; TIMED_ACTION waits for a click
				_begin_dwell()

func _on_body_exited(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return
	var exiting_id := str(body.get("char_id")) if body.get("char_id") != null else ""
	var remaining := _first_overlapping_character(body)
	var exiting_dweller := exiting_id != "" and exiting_id == _dwell_char_id
	if not exiting_dweller:
		# A bystander leaving must not break another character's click-gated work. A
		# TIMED_ACTION arrival can be data-layer-only, so preserve its synthetic range
		# while it is dwelling even when there is no physics overlap to rediscover.
		_player_in_range = remaining != null or _is_dwelling()
		return
	_dwell_pending = false
	_cancel_dwell()
	_dwell_progress = 0.0
	_dwell_char_id = ""
	_player_in_range = remaining != null
	if remaining != null and _proximity_dwell():
		_dwell_char_id = str(remaining.get("char_id")) if remaining.get("char_id") != null else ""
		_begin_dwell()

func _first_overlapping_character(excluding: Node3D = null) -> CharacterBody3D:
	# A one-shot can disable monitoring inside its dwell callback; Godot may still
	# deliver the queued body_exited signal afterward. Overlap queries are invalid
	# once monitoring is off, and there cannot be a replacement dweller anyway.
	if not monitoring:
		return null
	for candidate in get_overlapping_bodies():
		if candidate == excluding or not is_instance_valid(candidate):
			continue
		if candidate is CharacterBody3D:
			return candidate as CharacterBody3D
	return null

func _on_mouse_entered() -> void:
	if GridWorld._fx_debug:
		GridWorld._pf_trace("[outline] HIT interactable '%s' (used=%s enabled=%s managed=%s outline_target=%s)" % [
			name, _used, interaction_enabled, _feedback_managed, _outline_target != null])
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
		# The `command` action (right mouse) is the interact command (RTS-style). A `select` (left) click
		# is NEVER an interaction — it falls through to the player as a plain move/select, so clicking
		# past or grazing an object's pick volume never walks the character onto it.
		if event.is_action_pressed("command"):
			var viewport := get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
			submit_pointer_command()


## Uniform visible-surface command seam shared with OutlineSurfaceTarget and
## PushTarget. SelectionController's classified short click reaches this method
## through Player's production collision query; no caller mutates interaction or
## movement authority directly.
func submit_pointer_command(_event_position: Vector3 = Vector3.INF) -> bool:
	if _used or not interaction_enabled:
		# Direct Area hits can race the same capture/FIFO boundary as rendered
		# wrappers.  Preserve an exact target-specific refusal even though the
		# command no longer has authority to mutate or move anything.
		play_interaction_result(false)
		return false
	# `interaction_requested` is synchronous. A semantic route gate can therefore
	# mint this exact target's authoritative red/green result before emit returns.
	# Do not follow that result with queued-selection feedback: the queued pulse
	# clears the just-minted result and turns a visible refusal into a silent click.
	var result_before := get_player_interaction_presentation()
	var previous_request_owner := _interaction_request_owner
	_interaction_request_owner = active_character
	interaction_requested.emit(self, global_position)
	_interaction_request_owner = previous_request_owner
	var result_after := get_player_interaction_presentation()
	if int(result_after.get("presentation_serial", 0)) \
			> int(result_before.get("presentation_serial", 0)):
		var synchronous_result := str(result_after.get(
			"authority_result", result_after.get("result", "")))
		if synchronous_result in ["success", "rejected"]:
			return synchronous_result == "success"
	outline_selected.emit(self)
	return true


## Stable read-only command ownership seam. This value exists only for the
## synchronous signal delivery started by `submit_pointer_command`; it cannot be
## rewritten when a controller assigns a different party member to service the
## interaction.
func get_interaction_request_owner() -> String:
	return _interaction_request_owner


## Public query used only to keep a linked rendered command surface truthful.
## Wrong-character and scenario-preflight failures remain actionable: they are
## still clickable and produce their ordinary exact refusal after submission.
func is_pointer_command_available() -> bool:
	return interaction_enabled and not _used


func _sync_outline_target_command_availability() -> void:
	if _outline_target != null and is_instance_valid(_outline_target) \
			and _outline_target.has_method("set_interaction_command_enabled"):
		_outline_target.call(
			"set_interaction_command_enabled", is_pointer_command_available())

func play_selected_feedback() -> void:
	# Legacy burst API: the queued energy glow replaced the particle sprays entirely.
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
	# The name reads on EVERY hover — identification is free. Aster's data overlay only restyles
	# the readout (its cyan); it never gates whether a hovered object names itself.
	_set_identify_label_visible(active)
	# Plants rustle at a touch of attention; industrial props hold still on hover
	# (motion on every hover would be noise — the outline + verb already speak).
	if active and juice_profile == "plant" and interaction_enabled and not _used:
		InteractableJuice.rustle(_juice_meshes(), 0.045, 0.45)

## Aster's data overlay (de)activates: it tints the hover readout into the data register. The label
## itself follows plain hover either way.
func set_data_identify(active: bool) -> void:
	_data_identify = active
	_set_identify_label_visible(_hover_active)

func _identify_name() -> String:
	if description != "":
		return description
	if tutorial_label != "" and tutorial_label != "Click" and tutorial_label != InputLabels.action_label("command"):
		return tutorial_label
	return name.replace("_", " ").replace("Zone", "").strip_edges()

func _set_identify_label_visible(should_show: bool) -> void:
	if should_show and (_used or not interaction_enabled or _identify_name() == ""):
		return
	if should_show:
		_ensure_identify_label()
		_identify_label_3d.text = "// %s //" % _identify_name().to_upper()
		# Plain hover reads neutral white; Aster's data overlay tints it into the data register.
		_identify_label_3d.modulate = Color(0.45, 0.78, 1.0, 0.95) if _data_identify else Color(0.92, 0.95, 1.0, 0.95)
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
	if GridWorld._fx_debug:
		GridWorld._pf_trace("[outline] interactable '%s' _refresh_feedback want=%s -> forward to target=%s" % [
			name, want, _outline_target != null and is_instance_valid(_outline_target)])
	if _outline_target != null and is_instance_valid(_outline_target):
		_outline_target.set_highlight(want)

func set_interaction_enabled(active: bool) -> void:
	if active:
		set_process(true)  # re-evaluate per-frame work (self-disables when idle)
	else:
		_set_identify_label_visible(false)   # a dead object stops naming itself mid-hover
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
	if active and not _restoring_dwell_authority:
		call_deferred("_refresh_player_range")

func is_interaction_enabled() -> bool:
	return interaction_enabled

func apply_interactable_spec(spec_id: String) -> void:
	var catalog_script = load("res://scripts/game/objects/interactable_catalog.gd")
	if catalog_script != null:
		catalog_script.apply_spec(self, spec_id)
	if _tutorial_label_3d != null:
		_tutorial_label_3d.text = InputLabels.expand(tutorial_label) if tutorial_label != "" else InputLabels.action_label("command")
	if _collision_shape != null and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = interaction_radius
	if is_inside_tree():
		set_interaction_enabled(interaction_enabled)

func on_interaction_arrived() -> void:
	if _triggers_on_arrival():
		_trigger(false)
	elif _works_on_arrival():
		# Walked over via a click; now run the work/tend timer (the character is here, so it's in range),
		# and _on_dwell_complete fires the actual trigger once dwell_time elapses. This call itself is
		# the interaction coordinator's authoritative arrival receipt. GameState can still report the
		# movement as active until every listener of that same arrival signal has returned; treating that
		# transient flag as a new pending walk misses the already-consumed arrival and strands the action.
		_dwell_char_id = active_character
		_player_in_range = true
		_begin_dwell(true)

func _refresh_player_range() -> void:
	if _restoring_dwell_authority:
		return
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

## A meshless interactable's queued feedback lives on ITS OBJECT's outline target: the character-
## colored outline + energy glow while the interaction is committed/en route. No particles.
## The commit is also the CLICK moment — the object gives a small acknowledge nudge
## and touch devices feel a light tap (the "I heard you" beat; the full squash
## waits for the actual trigger on arrival).
func begin_queued_feedback(origin: Vector3 = Vector3.ZERO, queue_color: Color = Color(0, 0, 0, 0)) -> void:
	if _outline_target != null and is_instance_valid(_outline_target) and _outline_target.has_method("begin_queued_feedback"):
		_outline_target.call("begin_queued_feedback", origin, queue_color)
	if juice_profile != "none":
		InteractableJuice.punch(_juice_meshes(), 0.06, 0.22)
		InteractableJuice.tap(18)

func complete_queued_feedback() -> void:
	if _outline_target != null and is_instance_valid(_outline_target) and _outline_target.has_method("complete_queued_feedback"):
		_outline_target.call("complete_queued_feedback")

func cancel_queued_feedback() -> void:
	if _outline_target != null and is_instance_valid(_outline_target) and _outline_target.has_method("cancel_queued_feedback"):
		_outline_target.call("cancel_queued_feedback")

func get_outline_highlight_radius() -> float:
	return outline_highlight_radius if outline_highlight_radius > 0.0 else interaction_radius

func get_outline_highlight_origin() -> Vector3:
	return global_position + Vector3(0.0, outline_highlight_height, 0.0)

func get_interaction_target_position(_from_position: Vector3 = Vector3.ZERO, _requested_position: Vector3 = Vector3.INF) -> Vector3:
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
	return global_position

func reset() -> void:
	_owner_used_override = null
	_owner_enabled_override = null
	_used = false
	_player_in_range = false
	_dwell_progress = 0.0
	_progress_mat.albedo_color.a = 0.0
	# Re-arm the data layer too (clear triggered), so a one-shot can fire again.
	if _game_state != null and data_id != "" and _game_state.has_interactable(data_id):
		_game_state.reset_interactable(data_id)
	set_interaction_enabled(true)


## Object-owner restore seam for a staged one-shot mechanism. The enclosing mechanism already has the
## authoritative phase; this only retracts/mirrors the control presenter without overwriting an in-flight
## dwell record before this Interactable receives its own snapshot-restored callback.
func restore_one_shot_presenter(used: bool, enabled: bool) -> void:
	var was_restoring := _restoring_dwell_authority
	_restoring_dwell_authority = true
	_owner_used_override = used
	_owner_enabled_override = enabled
	# Owner projections can run every scheduler publication. Reapplying an
	# unchanged projection is not harmless: set_interaction_enabled() deliberately
	# cancels an in-flight dwell. Preserve the physical work beat unless authority
	# actually crossed a used/enabled boundary.
	if _used == used and interaction_enabled == enabled:
		_restoring_dwell_authority = was_restoring
		return
	_used = used
	set_interaction_enabled(enabled)
	_restoring_dwell_authority = was_restoring


func get_dwell_progress() -> float:
	return _dwell_progress / dwell_time if dwell_time > 0 else 0.0

func is_player_in_range() -> bool:
	return _player_in_range
