class_name BranchSpanProducer
extends Node3D

## Reusable mandatory-branch consequence kit.
##
## A character works a producer in an already-reachable branch. GameState immediately commits the
## scheduler-owned `extending -> bridged` phase, while this node derives both the visible extension
## and the GridWorld gap blocker from that authoritative phase. The route therefore remains closed
## throughout the delay, including halfway saves and replays, and opens only when GameState reaches
## `bridged`.

const BridgeCargoScene := preload("res://resources/models/elevator/bridge.glb")
const BRIDGE_VISUAL_SOURCE := "res://resources/models/elevator/bridge.glb"
const ProducerHousingMesh := preload(
	"res://resources/models/peris-sim/props/wellness_terminal/wellness_terminal_housing.obj"
)
const ProducerDisplayMesh := preload(
	"res://resources/models/peris-sim/props/wellness_terminal/wellness_terminal_display.obj"
)
const PRODUCER_VISUAL_SOURCE := \
		"res://resources/models/peris-sim/props/wellness_terminal/"
const STATE_CONTRACT := "branch_span_producer/v1"
const SOURCE_BRIDGE_LENGTH := 12.0

signal activation_rejected(character_id: String, reason: StringName)
signal extension_started(mechanism_id: StringName, state: Dictionary)
signal span_bridged(mechanism_id: StringName, state: Dictionary)
signal span_reset(mechanism_id: StringName, reason: StringName)

var _gs = null
var _scheduler = null
var _grid: GridWorld
var _producer_data_position := Vector3.ZERO
var _producer_render_position := Vector3.ZERO
var _span_render_start := Vector3.ZERO
var _span_render_end := Vector3.ZERO
var _blocker_cells: Array[Vector2i] = []
var _mechanism_id: StringName = &""
var _blocker_tag := ""
var _duration := 0.0
var _interaction_radius := 2.0
var _span_width := 2.4
var _required_character := ""
var _configured := false

# Presentation caches only. The phase/progress source of truth is GameState.
var _presented_phase: StringName = &"__uninitialized"
var _presented_progress := -1.0
var _blocker_conflicts: Array[Dictionary] = []

var _producer_interactable: Interactable
var _producer_visual: Node3D
var _producer_outline = null
var _span_root: Node3D
var _span_model: Node3D
var _span_body: StaticBody3D
var _span_collision: CollisionShape3D
var _runtime_built := false


## The blocker cells are declared data cells on GameState.grid. They must currently be ordinary
## walkable cells: a dynamic blocker represents the unbridged gap, and removing it must actually
## make the declared route traversable. `mechanism_id`, `blocker_tag`, and `duration` are required
## options so generated content cannot silently invent unstable instance-local identities.
func configure(
		game_state,
		scheduler,
		producer_data_position: Vector3,
		producer_render_position: Vector3,
		span_render_start: Vector3,
		span_render_end: Vector3,
		blocker_cells: Array,
		options: Dictionary = {}
	) -> bool:
	if _configured or game_state == null or scheduler == null or game_state.grid == null:
		return false
	var mechanism_id := StringName(str(options.get("mechanism_id", "")))
	var blocker_tag := str(options.get("blocker_tag", "")).strip_edges()
	var duration := float(options.get("duration", 0.0))
	var interaction_radius := float(options.get("interaction_radius", 2.0))
	var span_width := float(options.get("span_width", 2.4))
	if String(mechanism_id).is_empty() or blocker_tag.is_empty() or duration <= 0.0 \
			or interaction_radius <= 0.0 or span_width <= 0.0:
		return false
	if span_render_start.distance_to(span_render_end) < 0.1 or blocker_cells.is_empty():
		return false

	var grid := game_state.grid as GridWorld
	if grid == null:
		return false
	var normalized_cells: Array[Vector2i] = []
	for cell_variant in blocker_cells:
		var cell := _as_cell(cell_variant)
		if cell == Vector2i(-2147483648, -2147483648) \
				or not grid.is_in_bounds(cell.x, cell.y) \
				or grid.get_tile(cell.x, cell.y) == GridWorld.Tile.WALL:
			return false
		if normalized_cells.has(cell):
			continue
		if grid.dynamic_blockers.has(cell) \
				and str(grid.dynamic_blockers.get(cell, "")) != blocker_tag:
			return false
		normalized_cells.append(cell)
	if normalized_cells.is_empty():
		return false

	_gs = game_state
	_scheduler = scheduler
	_grid = grid
	_producer_data_position = producer_data_position
	_producer_render_position = producer_render_position
	_span_render_start = span_render_start
	_span_render_end = span_render_end
	_blocker_cells = normalized_cells
	_mechanism_id = mechanism_id
	_blocker_tag = blocker_tag
	_duration = duration
	_interaction_radius = interaction_radius
	_span_width = span_width
	_required_character = str(options.get("required_character", "")).strip_edges()
	_configured = true

	_ensure_runtime()
	_bind_producer_interactable_authority()
	_apply_layout()
	_wire_game_state_signals()
	_presented_phase = &"__uninitialized"
	_presented_progress = -1.0
	sync_from_game_state()
	return true


func get_producer_interactable() -> Interactable:
	return _producer_interactable


func get_interactables() -> Array[Node]:
	var result: Array[Node] = []
	if _producer_interactable != null:
		result.append(_producer_interactable)
	return result


func get_mechanism_id() -> StringName:
	return _mechanism_id


func get_blocker_cells() -> Array[Vector2i]:
	return _blocker_cells.duplicate()


func get_blocker_tag() -> String:
	return _blocker_tag


func producer_interactable_id() -> String:
	return "branch_span_producer:%s:terminal" % String(_mechanism_id)


func is_extending() -> bool:
	return _phase_state().get("phase", &"") == &"extending"


func is_bridged() -> bool:
	return _phase_state().get("phase", &"") == &"bridged"


## Retired compatibility seam. Supplying an actor id is not evidence that the corresponding body
## serviced this terminal; only the terminal's consumed interaction receipt may begin the span.
func activate(_character_id: String) -> bool:
	return false


## Commit only after the exact producer Interactable has synchronously spent its one-shot registry
## edge. This prevents headless helpers, stale callbacks, and caller-supplied actor ids from
## substituting for the visible body-at-terminal cause.
func _activate_from_source(source: Node) -> bool:
	if not _producer_receipt_pending(source):
		return false
	var character_id := str(source.get("active_character"))
	return _commit_activation(character_id)


func _commit_activation(character_id: String) -> bool:
	var reason := _activation_rejection(character_id)
	if reason != &"":
		activation_rejected.emit(character_id, reason)
		return false
	var blocker_payload: Array = []
	for cell in _blocker_cells:
		blocker_payload.append([cell.x, cell.y])
	return bool(_gs.command_begin_mechanism_phase(
		_mechanism_id,
		&"extending",
		_duration,
		&"bridged",
		{
			"mechanism_type": "branch_span_producer",
			"activated_by": character_id,
			"producer_data_position": GameEvent.v3_to_arr(_producer_data_position),
			"producer_render_position": GameEvent.v3_to_arr(_producer_render_position),
			"span_render_start": GameEvent.v3_to_arr(_span_render_start),
			"span_render_end": GameEvent.v3_to_arr(_span_render_end),
			"blocker_cells": blocker_payload,
			"blocker_tag": _blocker_tag,
		}
	))


func _validate_producer_trigger(source: Node, character_id: String) -> bool:
	return source != null and source == _producer_interactable \
		and _activation_rejection(character_id) == &""


func _producer_receipt_pending(source: Node) -> bool:
	if source == null or source != _producer_interactable \
			or not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return false
	var character_id := str(source.get("active_character"))
	if _activation_rejection(character_id) != &"":
		return false
	var data_id := str(source.get("data_id"))
	if _gs == null or data_id == "" or not _gs.has_interactable(data_id):
		return false
	var receipt: Dictionary = _gs.get_interactable(data_id)
	return bool(receipt.get("one_shot", false)) \
		and bool(receipt.get("triggered", false)) \
		and not _gs.is_interactable_enabled(data_id)


## Checkpoint reset is itself an authoritative event. The mechanism reset signal re-derives the
## dormant presentation and reinstalls only this kit's declared blockers.
func reset(reason: StringName = &"branch_span_reset") -> bool:
	if not _configured or _gs == null or not _gs.has_mechanism_phase(_mechanism_id):
		_apply_authoritative_truth()
		return false
	return bool(_gs.command_reset_mechanism_phase(_mechanism_id, reason))


func get_state() -> Dictionary:
	_apply_authoritative_truth()
	var phase_state := _phase_state()
	var phase := StringName(str(phase_state.get("phase", "dormant")))
	var owned_cells: Array[Vector2i] = []
	var blocked_cells: Array[Vector2i] = []
	if _grid != null:
		for cell in _blocker_cells:
			if _grid.dynamic_blockers.has(cell):
				blocked_cells.append(cell)
			if str(_grid.dynamic_blockers.get(cell, "")) == _blocker_tag:
				owned_cells.append(cell)
	return {
		"contract": STATE_CONTRACT,
		"mechanism_id": _mechanism_id,
		"phase": phase,
		"progress": float(phase_state.get("progress", 0.0)),
		"remaining": float(phase_state.get("remaining", 0.0)),
		"authoritative_phase": phase_state,
		"producer_data_position": _producer_data_position,
		"producer_render_position": _producer_render_position,
		"span_render_start": _span_render_start,
		"span_render_end": _span_render_end,
		"duration": _duration,
		"span_width": _span_width,
		"blocker_cells": _blocker_cells.duplicate(),
		"blocker_tag": _blocker_tag,
		"blocked_cells": blocked_cells,
		"owned_blocker_cells": owned_cells,
		"blocker_conflicts": _blocker_conflicts.duplicate(true),
		"producer_interaction_enabled": _producer_interactable != null \
				and _producer_interactable.is_interaction_enabled(),
		"bridge_visual_progress": _presented_progress,
		"bridge_collision_enabled": _span_collision != null and not _span_collision.disabled,
		"bridge_visual_source": BRIDGE_VISUAL_SOURCE,
		"producer_visual_source": PRODUCER_VISUAL_SOURCE,
	}


func serialize_state() -> Dictionary:
	return get_state().duplicate(true)


## Scene snapshots are diagnostic only. A presenter rebuilt after load/replay always trusts
## GameState's phase and derives its visual/collision/navigation state from that phase.
func restore_state(snapshot: Dictionary) -> bool:
	if str(snapshot.get("contract", "")) != STATE_CONTRACT or not _configured:
		return false
	sync_from_game_state()
	return true


func sync_from_game_state() -> void:
	_apply_authoritative_truth(true)


## Loading may land exactly after Interactable spent its one-shot and before this owner published a
## mechanism phase. Restore the child receipt first, then let absent/dormant mechanism truth re-arm
## it; an extending or bridged phase remains disabled. Repeated calls are idempotent.
func on_game_state_snapshot_restored() -> void:
	if _producer_interactable != null \
			and _producer_interactable.has_method("on_game_state_snapshot_restored"):
		_producer_interactable.on_game_state_snapshot_restored()
	_apply_authoritative_truth(true)


func _ready() -> void:
	_ensure_runtime()
	_apply_layout()
	if _configured:
		_wire_game_state_signals()
		sync_from_game_state()
	call_deferred("_wire_outline")


func _process(_delta: float) -> void:
	if _configured:
		_apply_authoritative_truth()


func _activation_rejection(character_id: String) -> StringName:
	if not _configured or _gs == null or _scheduler == null:
		return &"not_configured"
	if _gs.has_mechanism_phase(_mechanism_id):
		return &"already_committed"
	if _required_character != "" and character_id != _required_character:
		return &"wrong_character"
	if character_id.is_empty() or not _gs.characters.has(character_id):
		return &"unknown_character"
	if _gs.is_downed(character_id):
		return &"character_downed"
	if _gs.has_method("is_narratively_available") \
			and not bool(_gs.call("is_narratively_available", character_id)):
		return &"character_unavailable"
	if _gs.is_knocked_down(character_id) or _gs.is_moving(character_id) \
			or _gs.is_resting(character_id) or _gs.is_dodging(character_id) \
			or _gs.is_endocytosing(character_id) \
			or _gs.is_external_traversal_active(character_id) \
			or _gs.is_dragging(character_id) or _gs.is_field_restoring(character_id):
		return &"character_busy"
	if _grid != null and _grid.level_count > 1 \
			and int(_gs.get_character_level(character_id)) != int(
				_grid.level_for_y(_producer_data_position.y)
			):
		# Stacked decks can share x/z coordinates and their authored separation can
		# be smaller than this terminal's horizontal service radius. The body must
		# occupy the producer's actual navigation floor, not the room above/below.
		return &"wrong_navigation_level"
	if _gs.get_position(character_id).distance_to(_producer_data_position) \
			> _interaction_radius + 0.25:
		return &"out_of_range"
	return &""


func _phase_state() -> Dictionary:
	if not _configured or _gs == null:
		return {}
	return _gs.get_mechanism_phase_state(_mechanism_id)


func _apply_authoritative_truth(force_rearm_dormant: bool = false) -> void:
	if not _configured:
		return
	var phase_state := _phase_state()
	var phase := StringName(str(phase_state.get("phase", "dormant")))
	var progress := clampf(float(phase_state.get("progress", 0.0)), 0.0, 1.0)
	if phase == &"bridged":
		progress = 1.0
	var phase_changed := phase != _presented_phase
	var progress_changed := not is_equal_approx(progress, _presented_progress)

	# Navigation is derived from the phase, never the sampled animation. Extending remains blocked.
	_apply_blocker_truth(phase == &"bridged")
	if phase_changed or force_rearm_dormant:
		_apply_interaction_truth(phase, force_rearm_dormant)
	if phase_changed or progress_changed:
		_apply_span_progress(progress, phase == &"bridged")
	_presented_phase = phase
	_presented_progress = progress


func _apply_blocker_truth(bridged: bool) -> void:
	_blocker_conflicts.clear()
	if _grid == null:
		return
	for cell in _blocker_cells:
		var existing := str(_grid.dynamic_blockers.get(cell, ""))
		if bridged:
			if existing == _blocker_tag:
				_grid.remove_dynamic_blocker(cell)
			elif not existing.is_empty():
				_blocker_conflicts.append({"cell": cell, "owner": existing})
			continue
		if existing.is_empty():
			_grid.add_dynamic_blocker(cell, _blocker_tag)
		elif existing != _blocker_tag:
			_blocker_conflicts.append({"cell": cell, "owner": existing})


func _apply_interaction_truth(phase: StringName, force_rearm_dormant: bool) -> void:
	if _producer_interactable == null:
		return
	if phase == &"dormant":
		if (force_rearm_dormant or _presented_phase != &"dormant") \
				and _producer_interactable.is_node_ready():
			_producer_interactable.reset()
		else:
			_set_interactable_enabled(true)
	else:
		_set_interactable_enabled(false)


func _set_interactable_enabled(enabled: bool) -> void:
	if _producer_interactable == null \
			or _producer_interactable.is_interaction_enabled() == enabled:
		return
	if _producer_interactable.is_node_ready():
		_producer_interactable.set_interaction_enabled(enabled)
	else:
		_producer_interactable.interaction_enabled = enabled


func _apply_span_progress(progress: float, bridged: bool) -> void:
	if _span_root == null or _span_model == null:
		return
	var p := clampf(progress, 0.0, 1.0)
	var full_vector := _span_render_end - _span_render_start
	var full_length := full_vector.length()
	_span_root.position = _span_render_start
	# BridgeCargoScene's authored long X axis is rotated onto this root's local Z axis (matching the
	# existing hydraulic cargo use). Point that local Z axis at the declared endpoint so growth is
	# spatially truthful rather than merely changing scale beside the gap.
	_span_root.basis = _basis_with_z(full_vector.normalized())
	_span_model.visible = p > 0.0
	if p > 0.0:
		var current_length := maxf(0.01, full_length * p)
		_span_model.position = Vector3(0.0, 0.0, current_length * 0.5)
		_span_model.scale = Vector3(
			current_length / SOURCE_BRIDGE_LENGTH,
			0.35,
			0.80 * (_span_width / 2.4)
		)
	if _span_collision != null:
		_span_collision.position = Vector3(0.0, 0.02, full_length * 0.5)
		var box := _span_collision.shape as BoxShape3D
		if box != null:
			box.size = Vector3(_span_width, 0.22, full_length)
		_span_collision.disabled = not bridged


func _ensure_runtime() -> void:
	if _runtime_built:
		return
	_runtime_built = true

	_producer_visual = _build_producer_visual()
	add_child(_producer_visual)
	_producer_interactable = Interactable.new()
	_producer_interactable.name = "BranchSpanProducerInteraction"
	_producer_interactable.interaction_radius = _interaction_radius
	_producer_interactable.interactable_type = Interactable.InteractableType.INSPECTION
	_producer_interactable.description = "Extend the downstream bridge span"
	_producer_interactable.consequence_preview = "Bridge the marked downstream gap after a delay"
	_producer_interactable.tutorial_label = "EXTEND"
	_producer_interactable.one_shot = true
	_producer_interactable.required_character = _required_character
	_producer_interactable.set_pre_trigger_validator(_validate_producer_trigger)
	var interaction_shape := CollisionShape3D.new()
	interaction_shape.name = "CollisionShape3D"
	var interaction_sphere := SphereShape3D.new()
	interaction_sphere.radius = _interaction_radius
	interaction_shape.shape = interaction_sphere
	_producer_interactable.add_child(interaction_shape)
	_producer_interactable.interacted.connect(
		_on_producer_interacted.bind(_producer_interactable))
	add_child(_producer_interactable)

	_span_root = Node3D.new()
	_span_root.name = "BranchSpanPhysicalBridge"
	add_child(_span_root)
	_span_model = _build_bridge_model()
	_span_root.add_child(_span_model)
	_span_body = StaticBody3D.new()
	_span_body.name = "BridgeSurfaceCollision"
	_span_root.add_child(_span_body)
	_span_collision = CollisionShape3D.new()
	_span_collision.name = "BridgeSurfaceShape"
	_span_collision.shape = BoxShape3D.new()
	_span_collision.disabled = true
	_span_body.add_child(_span_collision)


func _apply_layout() -> void:
	if not _runtime_built:
		return
	if _producer_visual != null:
		_producer_visual.position = _producer_render_position
		_producer_visual.scale = Vector3.ONE * 0.62
	if _producer_interactable != null:
		_producer_interactable.position = _producer_render_position
		_producer_interactable.interaction_radius = _interaction_radius
		_producer_interactable.required_character = _required_character
		_producer_interactable.set_scheduler(_scheduler)
		_producer_interactable.set_movement_authority(_gs)
		_producer_interactable.set_meta("flat_authored_position", _producer_data_position)
		_producer_interactable.set_meta("interaction_target_position", _producer_render_position)
	_apply_span_progress(0.0, false)


## BranchSpanProducer is a reusable kit rather than a SceneChunk child, so it cannot rely on a host
## factory to register its terminal. Bind the terminal to one stable GameState id here; fresh
## presenters find the restored receipt instead of inventing an unbound local one-shot.
func _bind_producer_interactable_authority() -> void:
	if _gs == null or _producer_interactable == null:
		return
	var source_id := producer_interactable_id()
	if not _gs.has_interactable(source_id):
		_gs.register_interactable({
			"id": source_id,
			"position": _producer_data_position,
			"requires_hold": false,
			"hold_time": 0.0,
			"one_shot": true,
			"required_character": _required_character,
			"radius": _interaction_radius,
			"tutorial_label": "EXTEND",
			"enabled": true,
		})
	_producer_interactable.bind_data(_gs, source_id)


func _build_producer_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "ReusedBranchSpanTerminal"
	var housing := MeshInstance3D.new()
	housing.name = "WellnessTerminalHousingReuse"
	housing.mesh = ProducerHousingMesh
	root.add_child(housing)
	var display := MeshInstance3D.new()
	display.name = "WellnessTerminalDisplayReuse"
	display.mesh = ProducerDisplayMesh
	root.add_child(display)
	return root


func _build_bridge_model() -> Node3D:
	var model := BridgeCargoScene.instantiate() as Node3D
	if model == null:
		model = Node3D.new()
	model.name = "ReusedBridgeCargoSpan"
	for mesh_variant in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_variant as MeshInstance3D
		if mesh == null:
			continue
		var part_name := str(mesh.name)
		mesh.visible = (
			part_name.begins_with("Deck_")
			or part_name.begins_with("Girder_")
			or part_name.begins_with("Brace")
			or part_name.begins_with("Sill_")
			or part_name.begins_with("Header_")
			or part_name.begins_with("RedStrip_")
		)
	for collision_variant in model.find_children("*", "CollisionObject3D", true, false):
		var collision := collision_variant as CollisionObject3D
		if collision != null:
			collision.collision_layer = 0
			collision.collision_mask = 0
			collision.input_ray_pickable = false
	model.rotation.y = -PI * 0.5
	return model


func _basis_with_z(z_axis: Vector3) -> Basis:
	var reference := Vector3.UP
	if absf(z_axis.dot(reference)) > 0.96:
		reference = Vector3.FORWARD
	var x_axis := reference.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _as_cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Vector2:
		var v := value as Vector2
		return Vector2i(int(v.x), int(v.y))
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i(-2147483648, -2147483648)


func _on_producer_interacted(source: Node) -> void:
	if not _activate_from_source(source) and _producer_interactable != null \
			and _producer_interactable.is_node_ready():
		# Interactable has already consumed its local one-shot before emitting `interacted`. If the
		# authoritative proximity guard rejects, immediately re-arm so a bad click is not a soft-lock.
		_producer_interactable.reset()


func _wire_game_state_signals() -> void:
	if _gs == null:
		return
	if _gs.has_signal("mechanism_phase_started") \
			and not _gs.mechanism_phase_started.is_connected(_on_mechanism_phase_started):
		_gs.mechanism_phase_started.connect(_on_mechanism_phase_started)
	if _gs.has_signal("mechanism_phase_completed") \
			and not _gs.mechanism_phase_completed.is_connected(_on_mechanism_phase_completed):
		_gs.mechanism_phase_completed.connect(_on_mechanism_phase_completed)
	if _gs.has_signal("mechanism_phase_reset") \
			and not _gs.mechanism_phase_reset.is_connected(_on_mechanism_phase_reset):
		_gs.mechanism_phase_reset.connect(_on_mechanism_phase_reset)


func _unwire_game_state_signals() -> void:
	if _gs == null:
		return
	if _gs.has_signal("mechanism_phase_started") \
			and _gs.mechanism_phase_started.is_connected(_on_mechanism_phase_started):
		_gs.mechanism_phase_started.disconnect(_on_mechanism_phase_started)
	if _gs.has_signal("mechanism_phase_completed") \
			and _gs.mechanism_phase_completed.is_connected(_on_mechanism_phase_completed):
		_gs.mechanism_phase_completed.disconnect(_on_mechanism_phase_completed)
	if _gs.has_signal("mechanism_phase_reset") \
			and _gs.mechanism_phase_reset.is_connected(_on_mechanism_phase_reset):
		_gs.mechanism_phase_reset.disconnect(_on_mechanism_phase_reset)


func _on_mechanism_phase_started(mechanism_id: StringName, _state: Dictionary) -> void:
	if mechanism_id != _mechanism_id:
		return
	_apply_authoritative_truth()
	extension_started.emit(_mechanism_id, get_state())


func _on_mechanism_phase_completed(mechanism_id: StringName, phase: StringName) -> void:
	if mechanism_id != _mechanism_id or phase != &"bridged":
		return
	_apply_authoritative_truth()
	span_bridged.emit(_mechanism_id, get_state())


func _on_mechanism_phase_reset(mechanism_id: StringName, reason: StringName) -> void:
	if mechanism_id != _mechanism_id:
		return
	_apply_authoritative_truth(true)
	span_reset.emit(_mechanism_id, reason)


func _wire_outline() -> void:
	if not is_inside_tree() or _producer_interactable == null or _producer_outline != null:
		return
	var meshes: Array[MeshInstance3D] = []
	for mesh_variant in _producer_visual.find_children("*", "MeshInstance3D", true, false):
		if mesh_variant is MeshInstance3D and (mesh_variant as MeshInstance3D).mesh != null:
			meshes.append(mesh_variant as MeshInstance3D)
	if meshes.is_empty():
		return
	var manager := OutlineFeedbackManager.ensure(self)
	if manager == null:
		return
	_producer_outline = manager.outline_meshes(
		self, String(_mechanism_id) + "ProducerOutline", meshes,
		"terminal", maxf(1.0, _interaction_radius)
	)
	if _producer_outline != null:
		_producer_interactable.set_outline_target(_producer_outline)


func _exit_tree() -> void:
	# Do not release the dynamic blockers here. They are derived world truth and must not disappear
	# just because a presenter is recreated; the owning GridWorld is discarded with its scene.
	_unwire_game_state_signals()
