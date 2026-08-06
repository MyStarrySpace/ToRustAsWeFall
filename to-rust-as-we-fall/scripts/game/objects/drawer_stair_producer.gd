# gdlint: disable=max-file-lines,max-returns,class-definitions-order
class_name DrawerStairProducer
extends Node3D

## Save-authoritative six-index drawer-stair P-KIT for the Open Files.
##
## Each catalog lever toggles one category. Every drawer module assigned to that category visibly
## extends or retracts from one shared, versioned GameState record. A ramp link exists only when
## the fully extended category set exactly matches an authored solution AND those categories form
## a deep-to-shallow, non-rotten column. Other extended drawers remain useful physical cover.
##
## TypedTerminal v1 deliberately is not a receiver for this kit: its shipped vocabulary is
## one-shot (`open`, `reveal`, `reroute`, `lure`, `hold`), while an index is a repeatable physical
## toggle. Keep the owned lever Interactables until a canonical repeatable `toggle` subtype exists;
## mapping this to `door/open` or `flow/hold` would make the causal contract dishonest.

const ArchiveDrawerMesh := preload(
	"res://resources/models/generated-biomes/stacks_archive_spire/stacks_archive_spire_drawers.obj"
)
const ArchiveTerminalMesh := preload(
	"res://resources/models/generated-biomes/stacks_archive_spire/stacks_archive_spire_terminal.obj"
)
const DRAWER_VISUAL_SOURCE := \
		"res://resources/models/generated-biomes/stacks_archive_spire/" \
		+ "stacks_archive_spire_drawers.obj"
const LEVER_VISUAL_SOURCE := \
		"res://resources/models/generated-biomes/stacks_archive_spire/" \
		+ "stacks_archive_spire_terminal.obj"
const STATE_CONTRACT := "drawer_stair_producer/v1"
const AUTHORITY_VERSION := 1
const TYPED_TERMINAL_INTEGRATION_CONSTRAINT := 'TypedTerminal v1 has no repeatable toggle subtype.'
const AUTHORITY_PREFIX := "gameplay:drawer_stair_producer:"
const SOURCE_PREFIX := "drawer_stair_index:"
const MIN_TRANSITION_DURATION := 0.05
const POSITION_EPSILON := 0.05
const INVALID_CELL := Vector2i(-2147483648, -2147483648)

signal index_transition_started(index_id: String, target_extended: bool, state: Dictionary)
signal index_transition_completed(index_id: String, extended: bool, state: Dictionary)
signal staircase_state_changed(ready: bool, solved_columns: Array[String], state: Dictionary)
signal activation_rejected(index_id: String, character_id: String, reason: StringName)
signal staircase_reset(reason: StringName)

var _game_state: GameState
var _scheduler = null
var _grid: GridWorld
var _stair_id := ""
var _authority_key := ""
var _index_specs: Array[Dictionary] = []
var _index_by_id: Dictionary = {}
var _valid_active_sets: Array[Array] = []
var _route_blocker_cells: Array[Vector2i] = []
var _route_blocker_tag := ""
var _link_specs: Array[Dictionary] = []
var _link_owner := ""
var _duration := 1.2
var _interaction_radius := 1.8
var _required_character := ""
var _stagger_fraction := 0.08
var _configured := false
var _last_restore_valid := true
var _restoring := false

# Presentation and derived-world caches only.
var _lever_sources: Dictionary = {}
var _lever_visuals: Dictionary = {}
var _module_presenters: Dictionary = {}
var _armed_transition_serials: Dictionary = {}
var _presented_progress: Dictionary = {}
var _presented_ready := false
var _presented_columns: Array[String] = []
var _owned_cover_cells: Dictionary = {}
var _blocker_conflicts: Array[Dictionary] = []
var _link_conflicts: Array[Dictionary] = []


## `index_specs` contains one entry per category:
## `{index_id, lever_data_position, lever_render_position?, drawer_modules, cover_cells?}`.
## Modules may be passed directly from `StacksOpenFilesLayout`; `closed_position`,
## `extended_position` (or direction + extension), `collision_size`, `column`, `height`, `tint`,
## and `rotten` are retained.
##
## `topology` contains `{valid_active_sets, links, route_blocker_cells?, route_blocker_tag?}`.
## Each link is `{column_id, cell, from_level, to_level, type?: "ramp"}`. Route blockers are
## optional because an absent inter-level link is already a truthful vertical gate.
func configure(
		game_state: GameState,
		stair_id: String,
		index_specs: Array,
		topology: Dictionary,
		options: Dictionary = {}
	) -> bool:
	if _configured or game_state == null or game_state.grid == null \
			or game_state.scheduler == null:
		return false
	var normalized_id := stair_id.strip_edges()
	var normalized_indices := _normalize_index_specs(index_specs)
	var normalized_sets := _normalize_active_sets(
		topology.get("valid_active_sets", []), normalized_indices)
	var normalized_links := _normalize_links(
		game_state.grid, topology.get("links", []), normalized_indices)
	var blocker_cells := _normalize_cells(
		game_state.grid, topology.get("route_blocker_cells", []), true)
	var blocker_tag := str(topology.get("route_blocker_tag", "")).strip_edges()
	var duration := float(options.get("duration", 1.2))
	var radius := float(options.get("interaction_radius", 1.8))
	var stagger := float(options.get("stagger_fraction", 0.08))
	if normalized_id.is_empty() or normalized_indices.size() != 6 \
			or normalized_sets.is_empty() or normalized_links.is_empty() \
			or duration <= 0.0 or radius <= 0.0 or stagger < 0.0 or stagger >= 1.0:
		return false
	if not blocker_cells.is_empty() and blocker_tag.is_empty():
		return false
	if not _validate_closed_topology(game_state.grid, blocker_cells, blocker_tag, normalized_links):
		return false

	_game_state = game_state
	_scheduler = game_state.scheduler
	_grid = game_state.grid
	_stair_id = normalized_id
	_authority_key = AUTHORITY_PREFIX + _stair_id
	_index_specs = normalized_indices
	_index_by_id.clear()
	for spec in _index_specs:
		_index_by_id[str(spec.get("index_id", ""))] = spec
	_valid_active_sets = normalized_sets
	_route_blocker_cells = blocker_cells
	_route_blocker_tag = blocker_tag
	_link_specs = normalized_links
	_link_owner = "drawer_stair:%s" % _stair_id
	_duration = duration
	_interaction_radius = radius
	_required_character = str(options.get("required_character", "")).strip_edges()
	_stagger_fraction = stagger
	_configured = true

	_build_runtime()
	if not sync_from_game_state():
		return false
	set_process(true)
	return true


func authority_state_key() -> String:
	return _authority_key


func get_stair_id() -> String:
	return _stair_id


func get_index_ids() -> Array[String]:
	var ids: Array[String] = []
	for spec in _index_specs:
		ids.append(str(spec.get("index_id", "")))
	return ids


func get_index_interactables() -> Array[Node]:
	var result: Array[Node] = []
	for index_id in get_index_ids():
		var source: Variant = _lever_sources.get(index_id)
		if source is Node:
			result.append(source as Node)
	return result


func get_index_interactable(index_id: String) -> Interactable:
	var value: Variant = _lever_sources.get(index_id)
	return value as Interactable if value is Interactable else null


func index_interactable_id(index_id: String) -> String:
	return "%s%s:%s" % [SOURCE_PREFIX, _stair_id, index_id]


func is_staircase_ready() -> bool:
	return not _solved_columns(_authority_record()).is_empty()


func is_index_extended(index_id: String) -> bool:
	var state := _index_state_from_record(_authority_record(), index_id)
	return str(state.get("phase", "")) == "extended"


func get_index_state(index_id: String) -> Dictionary:
	var state := _index_state_from_record(_authority_record(), index_id)
	if state.is_empty():
		return {}
	var out := state.duplicate(true)
	out["progress"] = _index_progress_at(state, _now())
	out["remaining"] = maxf(0.0, float(state.get("deadline", _now())) - _now()) \
			if str(state.get("phase", "")) in ["extending", "retracting"] else 0.0
	return out


## No public actor-id toggle exists. Canonical toggles must consume their exact physical lever.
func toggle_index(_index_id: String, _character_id: String) -> bool:
	return false


func reset(reason: StringName = &"drawer_stair_reset") -> bool:
	if not _configured or _game_state == null:
		return false
	var current := _authority_record()
	if _record_is_baseline(current):
		_apply_authoritative_truth(true)
		return false
	_cancel_all_transition_tags()
	var reset_record := _baseline_record()
	reset_record["reset_reason"] = str(reason)
	reset_record["reset_tick"] = _now()
	reset_record["reset_serial"] = int(current.get("reset_serial", 0)) + 1
	for index_id in get_index_ids():
		var old_state := _index_state_from_record(current, index_id)
		var reset_state := _index_state_from_record(reset_record, index_id)
		reset_state["accepted_trigger_count"] = int(old_state.get(
			"accepted_trigger_count", _source_trigger_count(index_id)))
		_set_index_state(reset_record, index_id, reset_state)
	_game_state.set_world_state(_authority_key, reset_record)
	_reconcile_sources(reset_record)
	_apply_authoritative_truth(true)
	staircase_reset.emit(reason)
	return true


func on_game_state_snapshot_restored() -> bool:
	return sync_from_game_state()


func sync_from_game_state() -> bool:
	if not _configured:
		_last_restore_valid = false
		return false
	_restoring = true
	_cancel_all_transition_tags()
	var record := _authority_record()
	if record.is_empty():
		record = _baseline_record()
	elif not _valid_record(record):
		_last_restore_valid = false
		_apply_baseline_presentation_only()
		_restoring = false
		return false
	_last_restore_valid = true
	_reconcile_sources(record)
	_rearm_transitions(record)
	_apply_authoritative_truth(true)
	_restoring = false
	return true


func get_state() -> Dictionary:
	var record := _authority_record()
	if record.is_empty():
		record = _baseline_record()
	var index_states: Array[Dictionary] = []
	for index_id in get_index_ids():
		var state := get_index_state(index_id)
		state["index_id"] = index_id
		index_states.append(state)
	var solved := _solved_columns(record)
	return {
		"contract": STATE_CONTRACT,
		"version": AUTHORITY_VERSION,
		"stair_id": _stair_id,
		"authority_key": _authority_key,
		"restore_valid": _last_restore_valid,
		"index_states": index_states,
		"active_indices": _fully_extended_indices(record),
		"valid_active_sets": _valid_active_sets.duplicate(true),
		"solved_columns": solved,
		"staircase_ready": not solved.is_empty(),
		"route_blocker_cells": _route_blocker_cells.duplicate(),
		"route_blocker_tag": _route_blocker_tag,
		"installed_link_count": _installed_link_count(),
		"enabled_drawer_collision_count": _enabled_collision_count(),
		"owned_cover_cells": _owned_cover_cells.keys(),
		"blocker_conflicts": _blocker_conflicts.duplicate(true),
		"link_conflicts": _link_conflicts.duplicate(true),
		"drawer_visual_source": DRAWER_VISUAL_SOURCE,
		"lever_visual_source": LEVER_VISUAL_SOURCE,
	}


func serialize_state() -> Dictionary:
	return get_state().duplicate(true)


func restore_state(snapshot: Dictionary) -> bool:
	if str(snapshot.get("contract", "")) != STATE_CONTRACT \
			or str(snapshot.get("stair_id", "")) != _stair_id:
		return false
	return sync_from_game_state()


func _build_runtime() -> void:
	for index_spec in _index_specs:
		var index_id := str(index_spec.get("index_id", ""))
		_build_index_lever(index_id, index_spec)
		_build_index_modules(index_id, index_spec)


func _build_index_lever(index_id: String, spec: Dictionary) -> void:
	var data_position: Vector3 = spec.get("lever_data_position", Vector3.ZERO)
	var render_position: Vector3 = spec.get("lever_render_position", data_position)
	var visual := Node3D.new()
	visual.name = "%sIndexLeverVisual" % index_id.to_pascal_case()
	visual.position = render_position
	var mesh := MeshInstance3D.new()
	mesh.name = "ReusedArchiveTerminal"
	mesh.mesh = ArchiveTerminalMesh
	mesh.scale = Vector3.ONE * 0.42
	visual.add_child(mesh)
	var label := Label3D.new()
	label.name = "IndexLabel"
	label.position = Vector3(0.0, 1.55, 0.08)
	label.text = str(spec.get("label", index_id)).to_upper()
	label.font_size = 34
	label.pixel_size = 0.003
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = _as_color(spec.get("tint", Color(0.35, 0.8, 0.88)))
	label.outline_modulate = Color(0.01, 0.015, 0.02, 0.95)
	label.outline_size = 8
	visual.add_child(label)
	add_child(visual)
	_lever_visuals[index_id] = visual

	var source := Interactable.new()
	source.name = "%sIndexLever" % index_id.to_pascal_case()
	source.position = render_position
	source.interaction_radius = _interaction_radius
	source.interactable_type = Interactable.InteractableType.INSPECTION
	source.description = "Toggle the %s index" % label.text
	source.consequence_preview = "Extend or retract every %s drawer" % label.text
	source.tutorial_label = "TOGGLE"
	source.one_shot = true
	source.required_character = _required_character
	source.set_scheduler(_scheduler)
	source.set_movement_authority(_game_state)
	source.set_meta("flat_authored_position", data_position)
	source.set_meta("interaction_target_position", render_position)
	source.set_meta("drawer_stair_index_id", index_id)
	source.set_pre_trigger_validator(_validate_lever_trigger.bind(index_id))
	var interaction_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = _interaction_radius
	interaction_shape.shape = sphere
	source.add_child(interaction_shape)
	source.interacted.connect(_on_index_interacted.bind(index_id, source))
	add_child(source)
	_register_index_source(index_id, data_position)
	source.bind_data(_game_state, index_interactable_id(index_id))
	_lever_sources[index_id] = source

	# The reusable archive terminal is the visible cause, while `source` owns the exact interaction
	# receipt. Wrap that mesh in the shared surface target so hover/click feedback stays visible no
	# matter whether the physics ray finds the mesh hull or the source Area first.
	var manager := OutlineFeedbackManager.ensure(self)
	if manager != null:
		var outline := manager.outline_meshes(
			self, "%sIndexLeverOutline" % index_id.to_pascal_case(), [mesh],
			index_interactable_id(index_id), maxf(1.0, _interaction_radius))
		if outline != null:
			outline.set_interaction_delegate(source)
			source.set_outline_target(outline)


func _register_index_source(index_id: String, position: Vector3) -> void:
	var source_id := index_interactable_id(index_id)
	if _game_state.has_interactable(source_id):
		return
	_game_state.register_interactable({
		"id": source_id,
		"position": position,
		"requires_hold": false,
		"hold_time": 0.0,
		"one_shot": true,
		"required_character": _required_character,
		"radius": _interaction_radius,
		"tutorial_label": "TOGGLE",
		"enabled": true,
	})


func _build_index_modules(index_id: String, spec: Dictionary) -> void:
	var presenters: Array[Dictionary] = []
	for module_spec_v in spec.get("drawer_modules", []) as Array:
		var module_spec := (module_spec_v as Dictionary).duplicate(true)
		var root := Node3D.new()
		root.name = str(module_spec.get("id", "%sDrawer" % index_id)).to_pascal_case()
		root.position = module_spec.get("closed_position", Vector3.ZERO)
		root.set_meta("drawer_stair_index_id", index_id)
		root.set_meta("drawer_stair_column", str(module_spec.get("column", "")))
		root.set_meta("drawer_stair_rotten", bool(module_spec.get("rotten", false)))
		var visual := MeshInstance3D.new()
		visual.name = "ReusedArchiveDrawerBank"
		visual.mesh = ArchiveDrawerMesh
		_fit_drawer_visual(visual, module_spec)
		_apply_module_material(visual, module_spec)
		root.add_child(visual)
		var body := StaticBody3D.new()
		body.name = "ExtendedDrawerCollision"
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = module_spec.get("collision_size", Vector3(3.0, 0.65, 1.5))
		collision.shape = shape
		collision.position = module_spec.get("collision_offset", Vector3.ZERO)
		collision.disabled = true
		body.add_child(collision)
		root.add_child(body)
		add_child(root)
		presenters.append({
			"root": root,
			"visual": visual,
			"collision": collision,
			"spec": module_spec,
		})
	_module_presenters[index_id] = presenters


func _validate_lever_trigger(source: Node, character_id: String, index_id: String) -> bool:
	if source == null or source != _lever_sources.get(index_id):
		return false
	var reason := _character_rejection(character_id, index_id)
	if reason != &"":
		activation_rejected.emit(index_id, character_id, reason)
		return false
	return true


func _on_index_interacted(index_id: String, source: Interactable) -> void:
	if not _lever_receipt_pending(index_id, source) or not _commit_index_toggle(index_id, source):
		if source != null and source.is_node_ready():
			source.reset()
		return
	# The record already owns the accepted count and transition before this retryable source rearms.
	if source != null and source.is_node_ready():
		source.reset()


func _lever_receipt_pending(index_id: String, source: Interactable) -> bool:
	if source == null or source != _lever_sources.get(index_id) \
			or not bool(source.one_shot) or not bool(source.get("_used")) \
			or source.is_interaction_enabled():
		return false
	var character_id := str(source.active_character)
	if _character_rejection(character_id, index_id) != &"":
		return false
	var source_id := index_interactable_id(index_id)
	if not _game_state.has_interactable(source_id):
		return false
	var receipt := _game_state.get_interactable(source_id)
	var accepted := int(_index_state_from_record(
		_authority_or_baseline(), index_id).get("accepted_trigger_count", 0))
	return bool(receipt.get("one_shot", false)) \
		and bool(receipt.get("triggered", false)) \
		and not _game_state.is_interactable_enabled(source_id) \
		and int(receipt.get("trigger_count", 0)) > accepted \
		and str(receipt.get("last_trigger_character", "")) == character_id


func _commit_index_toggle(index_id: String, source: Interactable) -> bool:
	var record := _authority_or_baseline()
	if not _valid_record(record):
		return false
	var state := _index_state_from_record(record, index_id)
	var now := _now()
	var current_progress := _index_progress_at(state, now)
	var currently_targets_extended := float(state.get("progress_target", 0.0)) >= 0.5
	var target := 0.0 if currently_targets_extended else 1.0
	var transition_duration := maxf(
		MIN_TRANSITION_DURATION,
		_duration * absf(target - current_progress)
	)
	var serial := int(state.get("transition_serial", 0)) + 1
	var character_id := str(source.active_character)
	var source_id := index_interactable_id(index_id)
	var receipt := _game_state.get_interactable(source_id)
	state["phase"] = "extending" if target > current_progress else "retracting"
	state["progress_start"] = current_progress
	state["progress_target"] = target
	state["start_tick"] = now
	state["deadline"] = now + transition_duration
	state["transition_serial"] = serial
	state["accepted_trigger_count"] = int(receipt.get("trigger_count", 0))
	state["last_actor"] = character_id
	state["receipt_provenance"] = _source_provenance(index_id, receipt, character_id, now)
	_set_index_state(record, index_id, state)
	record["last_change_tick"] = now
	record["last_changed_index"] = index_id
	# Complete portable authority is visible before any blocker, link, collision, or animation moves.
	_game_state.set_world_state(_authority_key, record)
	_arm_transition(index_id, state)
	_apply_authoritative_truth(true)
	index_transition_started.emit(index_id, target >= 0.5, get_state())
	return true


func _complete_index_transition(index_id: String, expected_serial: int) -> void:
	var record := _authority_record()
	if not _valid_record(record):
		return
	var state := _index_state_from_record(record, index_id)
	if int(state.get("transition_serial", -1)) != expected_serial \
			or not str(state.get("phase", "")) in ["extending", "retracting"]:
		return
	var target := clampf(float(state.get("progress_target", 0.0)), 0.0, 1.0)
	if _now() + 0.000001 < float(state.get("deadline", INF)):
		return
	state["phase"] = "extended" if target >= 0.5 else "retracted"
	state["progress_start"] = target
	state["progress_target"] = target
	state["start_tick"] = float(state.get("deadline", _now()))
	state["deadline"] = float(state.get("deadline", _now()))
	_set_index_state(record, index_id, state)
	record["last_change_tick"] = _now()
	_game_state.set_world_state(_authority_key, record)
	_armed_transition_serials.erase(index_id)
	_apply_authoritative_truth(true)
	if not _restoring:
		index_transition_completed.emit(index_id, target >= 0.5, get_state())


func _authority_record() -> Dictionary:
	if not _configured or _game_state == null:
		return {}
	var value: Variant = _game_state.get_world_state(_authority_key, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _authority_or_baseline() -> Dictionary:
	var record := _authority_record()
	return record if not record.is_empty() else _baseline_record()


func _baseline_record() -> Dictionary:
	var states: Array[Dictionary] = []
	for index_id in get_index_ids():
		states.append({
			"index_id": index_id,
			"phase": "retracted",
			"progress_start": 0.0,
			"progress_target": 0.0,
			"start_tick": 0.0,
			"deadline": 0.0,
			"transition_serial": 0,
			"accepted_trigger_count": 0,
			"last_actor": "",
			"receipt_provenance": {},
		})
	return {
		"contract": STATE_CONTRACT,
		"version": AUTHORITY_VERSION,
		"stair_id": _stair_id,
		"phase": "ready_for_selection",
		"index_states": states,
		"last_change_tick": 0.0,
		"last_changed_index": "",
		"reset_serial": 0,
	}


func _valid_record(record: Dictionary) -> bool:
	if str(record.get("contract", "")) != STATE_CONTRACT \
			or int(record.get("version", 0)) != AUTHORITY_VERSION \
			or str(record.get("stair_id", "")) != _stair_id:
		return false
	var states: Variant = record.get("index_states", [])
	if not states is Array or (states as Array).size() != _index_specs.size():
		return false
	var seen := {}
	for state_v in states as Array:
		if not state_v is Dictionary:
			return false
		var state := state_v as Dictionary
		var index_id := str(state.get("index_id", ""))
		var phase := str(state.get("phase", ""))
		var progress_start := float(state.get("progress_start", -1.0))
		var progress_target := float(state.get("progress_target", -1.0))
		var start_tick := float(state.get("start_tick", -1.0))
		var deadline := float(state.get("deadline", -1.0))
		var accepted := int(state.get("accepted_trigger_count", -1))
		if not _index_by_id.has(index_id) or seen.has(index_id) \
				or not phase in ["retracted", "extending", "extended", "retracting"] \
				or not is_finite(progress_start) or not is_finite(progress_target) \
				or progress_start < 0.0 or progress_start > 1.0 \
				or progress_target < 0.0 or progress_target > 1.0 \
				or not is_finite(start_tick) or not is_finite(deadline) \
				or start_tick < 0.0 or deadline < start_tick \
				or int(state.get("transition_serial", -1)) < 0 or accepted < 0:
			return false
		if phase == "retracted" and (progress_start != 0.0 or progress_target != 0.0):
			return false
		if phase == "extended" and (progress_start != 1.0 or progress_target != 1.0):
			return false
		if phase == "extending" and progress_target <= progress_start:
			return false
		if phase == "retracting" and progress_target >= progress_start:
			return false
		if accepted > _source_trigger_count(index_id):
			return false
		if accepted > 0 and not state.get("receipt_provenance", {}) is Dictionary:
			return false
		seen[index_id] = true
	return seen.size() == _index_specs.size()


func _record_is_baseline(record: Dictionary) -> bool:
	if record.is_empty():
		return true
	if not _valid_record(record):
		return false
	for index_id in get_index_ids():
		if str(_index_state_from_record(record, index_id).get("phase", "")) != "retracted":
			return false
	return true


func _index_state_from_record(record: Dictionary, index_id: String) -> Dictionary:
	for value in record.get("index_states", []) as Array:
		if value is Dictionary and str((value as Dictionary).get("index_id", "")) == index_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _set_index_state(record: Dictionary, index_id: String, state: Dictionary) -> void:
	var states: Array = record.get("index_states", [])
	for index in range(states.size()):
		var value: Variant = states[index]
		if value is Dictionary and str((value as Dictionary).get("index_id", "")) == index_id:
			states[index] = state.duplicate(true)
			record["index_states"] = states
			return


func _index_progress_at(state: Dictionary, tick: float) -> float:
	var phase := str(state.get("phase", "retracted"))
	if phase == "retracted":
		return 0.0
	if phase == "extended":
		return 1.0
	var start := float(state.get("start_tick", tick))
	var deadline := float(state.get("deadline", start))
	var from := clampf(float(state.get("progress_start", 0.0)), 0.0, 1.0)
	var target := clampf(float(state.get("progress_target", from)), 0.0, 1.0)
	if deadline <= start:
		return target
	return lerpf(from, target, clampf((tick - start) / (deadline - start), 0.0, 1.0))


func _arm_transition(index_id: String, state: Dictionary) -> bool:
	var phase := str(state.get("phase", ""))
	if not phase in ["extending", "retracting"]:
		return false
	var serial := int(state.get("transition_serial", -1))
	var deadline := float(state.get("deadline", -1.0))
	if serial < 0 or deadline < 0.0:
		return false
	var tag := _transition_tag(index_id)
	_scheduler.cancel_tag(tag)
	if deadline <= _now() + 0.000001:
		_complete_index_transition(index_id, serial)
		return true
	var handle := int(_scheduler.schedule_at(
		deadline,
		_complete_index_transition.bind(index_id, serial),
		tag
	))
	if handle <= 0:
		return false
	_armed_transition_serials[index_id] = serial
	return true


func _rearm_transitions(record: Dictionary) -> void:
	for index_id in get_index_ids():
		var state := _index_state_from_record(record, index_id)
		if str(state.get("phase", "")) in ["extending", "retracting"]:
			_arm_transition(index_id, state)


func _cancel_all_transition_tags() -> void:
	if _scheduler == null:
		return
	for index_id in get_index_ids():
		_scheduler.cancel_tag(_transition_tag(index_id))
	_armed_transition_serials.clear()


func _transition_tag(index_id: String) -> String:
	return "drawer_stair_%s_%s_transition" % [_stair_id, index_id]


func _now() -> float:
	return float(_scheduler.get_current_tick()) if _scheduler != null else 0.0


func _source_trigger_count(index_id: String) -> int:
	if _game_state == null:
		return 0
	var source_id := index_interactable_id(index_id)
	if not _game_state.has_interactable(source_id):
		return 0
	return int(_game_state.get_interactable(source_id).get("trigger_count", 0))


func _source_provenance(
		index_id: String,
		receipt: Dictionary,
		character_id: String,
		accepted_tick: float
	) -> Dictionary:
	var spec: Dictionary = _index_by_id.get(index_id, {})
	var position: Vector3 = spec.get("lever_data_position", Vector3.ZERO)
	return {
		"source_contract": "drawer_stair_index_lever/v1",
		"source_id": index_interactable_id(index_id),
		"index_id": index_id,
		"actor": character_id,
		"source_trigger_count": int(receipt.get("trigger_count", 0)),
		"source_position": [position.x, position.y, position.z],
		"accepted_tick": accepted_tick,
	}


func _reconcile_sources(record: Dictionary) -> void:
	for index_id in get_index_ids():
		var source := get_index_interactable(index_id)
		if source == null:
			continue
		if source.has_method("on_game_state_snapshot_restored"):
			source.on_game_state_snapshot_restored()
		var source_id := index_interactable_id(index_id)
		if not _game_state.has_interactable(source_id):
			continue
		var receipt := _game_state.get_interactable(source_id)
		var accepted := int(_index_state_from_record(
			record, index_id).get("accepted_trigger_count", 0))
		var trigger_count := int(receipt.get("trigger_count", 0))
		# A trigger newer than authority is the accepted-before-owner seam: rearm without toggling.
		# An accepted trigger is also rearmed because index levers are reusable selectors.
		if bool(receipt.get("triggered", false)) or not _game_state.is_interactable_enabled(source_id):
			source.reset()
		elif bool(source.get("_used")) or not source.is_interaction_enabled():
			source.restore_one_shot_presenter(false, true)
		if trigger_count < accepted:
			_last_restore_valid = false


func _character_rejection(character_id: String, index_id: String) -> StringName:
	if not _configured or _game_state == null or not _index_by_id.has(index_id):
		return &"not_configured"
	if character_id.is_empty() or not _game_state.characters.has(character_id):
		return &"unknown_character"
	if _required_character != "" and character_id != _required_character:
		return &"wrong_character"
	if _game_state.is_downed(character_id):
		return &"character_downed"
	if _game_state.has_method("is_narratively_available") \
			and not bool(_game_state.call("is_narratively_available", character_id)):
		return &"character_unavailable"
	if _game_state.is_knocked_down(character_id) or _game_state.is_moving(character_id) \
			or _game_state.is_resting(character_id) or _game_state.is_dodging(character_id) \
			or _game_state.is_endocytosing(character_id) \
			or _game_state.is_external_traversal_active(character_id) \
			or _game_state.is_dragging(character_id) \
			or _game_state.is_field_restoring(character_id):
		return &"character_busy"
	var spec: Dictionary = _index_by_id[index_id]
	var data_position: Vector3 = spec.get("lever_data_position", Vector3.ZERO)
	if _grid.level_count > 1 and int(_game_state.get_character_level(character_id)) \
			!= int(_grid.level_for_y(data_position.y)):
		return &"wrong_navigation_level"
	if _game_state.get_position(character_id).distance_to(data_position) \
			> _interaction_radius + 0.25:
		return &"out_of_range"
	return &""


func _process(_delta: float) -> void:
	if _configured:
		_apply_authoritative_truth()


func _apply_authoritative_truth(force: bool = false) -> void:
	var record := _authority_record()
	if record.is_empty():
		record = _baseline_record()
	if not _valid_record(record):
		_apply_baseline_presentation_only()
		return
	for index_id in get_index_ids():
		_apply_index_presentation(index_id, _index_state_from_record(record, index_id), force)
	var solved := _solved_columns(record)
	_apply_route_blockers(not solved.is_empty())
	_apply_cover_blockers(record, solved)
	_apply_link_truth(solved)
	var ready := not solved.is_empty()
	if force or ready != _presented_ready or solved != _presented_columns:
		var changed := ready != _presented_ready or solved != _presented_columns
		_presented_ready = ready
		_presented_columns = solved.duplicate()
		if changed and not _restoring:
			staircase_state_changed.emit(ready, solved.duplicate(), get_state())


func _apply_baseline_presentation_only() -> void:
	var baseline := _baseline_record()
	for index_id in get_index_ids():
		_apply_index_presentation(
			index_id, _index_state_from_record(baseline, index_id), true)
	_apply_route_blockers(false)
	_apply_cover_blockers(baseline, [])
	_apply_link_truth([])
	_presented_ready = false
	_presented_columns.clear()


func _apply_index_presentation(index_id: String, state: Dictionary, force: bool) -> void:
	var progress := clampf(_index_progress_at(state, _now()), 0.0, 1.0)
	if not force and is_equal_approx(float(_presented_progress.get(index_id, -1.0)), progress):
		return
	_presented_progress[index_id] = progress
	var presenters: Array = _module_presenters.get(index_id, [])
	for module_index in range(presenters.size()):
		var entry := presenters[module_index] as Dictionary
		var spec := entry.get("spec", {}) as Dictionary
		var root := entry.get("root") as Node3D
		var collision := entry.get("collision") as CollisionShape3D
		var local_progress := _module_progress(progress, module_index, presenters.size())
		var eased := local_progress * local_progress * (3.0 - 2.0 * local_progress)
		var closed: Vector3 = spec.get("closed_position", Vector3.ZERO)
		var extended: Vector3 = spec.get("extended_position", closed)
		if root != null:
			root.position = closed.lerp(extended, eased)
		if collision != null:
			collision.disabled = str(state.get("phase", "")) != "extended"
	var lever: Node3D = _lever_visuals.get(index_id)
	if lever != null:
		lever.rotation.y = lerpf(0.0, -0.22, progress)


func _module_progress(global_progress: float, module_index: int, module_count: int) -> float:
	if module_count <= 1 or _stagger_fraction <= 0.0:
		return global_progress
	var max_offset := _stagger_fraction * float(module_count - 1)
	var span := maxf(0.0001, 1.0 - max_offset)
	return clampf((global_progress - _stagger_fraction * float(module_index)) / span, 0.0, 1.0)


func _apply_route_blockers(staircase_ready: bool) -> void:
	_blocker_conflicts.clear()
	for cell in _route_blocker_cells:
		var existing := str(_grid.dynamic_blockers.get(cell, ""))
		if staircase_ready:
			if existing == _route_blocker_tag:
				_grid.remove_dynamic_blocker(cell)
			elif not existing.is_empty():
				_blocker_conflicts.append({"kind": "route", "cell": cell, "owner": existing})
		elif existing.is_empty():
			_grid.add_dynamic_blocker(cell, _route_blocker_tag)
		elif existing != _route_blocker_tag:
			_blocker_conflicts.append({"kind": "route", "cell": cell, "owner": existing})


func _apply_cover_blockers(record: Dictionary, solved_columns: Array[String]) -> void:
	var desired: Dictionary = {}
	for index_id in _fully_extended_indices(record):
		var index_spec: Dictionary = _index_by_id.get(index_id, {})
		var index_cells := _cells_from_values(index_spec.get("cover_cells", []))
		for cell in index_cells:
			desired[cell] = _cover_owner(index_id)
		for module_v in index_spec.get("drawer_modules", []) as Array:
			var module := module_v as Dictionary
			if str(module.get("column", "")) in solved_columns:
				continue
			for cell in _module_cover_cells(module):
				desired[cell] = _cover_owner(index_id)

	for cell_v in _owned_cover_cells.keys():
		var cell := cell_v as Vector2i
		var old_owner := str(_owned_cover_cells[cell])
		if desired.has(cell) and str(desired[cell]) == old_owner:
			continue
		if str(_grid.dynamic_blockers.get(cell, "")) == old_owner:
			_grid.remove_dynamic_blocker(cell)
		_owned_cover_cells.erase(cell)
	for cell_v in desired.keys():
		var cell := cell_v as Vector2i
		var owner := str(desired[cell])
		var existing := str(_grid.dynamic_blockers.get(cell, ""))
		if existing.is_empty():
			_grid.add_dynamic_blocker(cell, owner)
			_owned_cover_cells[cell] = owner
		elif existing == owner:
			_owned_cover_cells[cell] = owner
		else:
			_blocker_conflicts.append({"kind": "cover", "cell": cell, "owner": existing})


func _module_cover_cells(module: Dictionary) -> Array[Vector2i]:
	var explicit := _cells_from_values(module.get("cover_cells", []))
	if not explicit.is_empty():
		return explicit
	var extended: Vector3 = module.get("extended_position", Vector3.INF)
	if not extended.is_finite():
		return []
	var cell := _grid.world_to_grid(extended)
	if not _grid.is_in_bounds(cell.x, cell.y) \
			or _grid.get_tile(cell.x, cell.y) == GridWorld.Tile.WALL:
		return []
	return [cell]


func _cover_owner(index_id: String) -> String:
	return "%s:cover:%s" % [_link_owner, index_id]


func _apply_link_truth(solved_columns: Array[String]) -> void:
	_link_conflicts.clear()
	for link in _link_specs:
		var should_exist := str(link.get("column_id", "")) in solved_columns
		var forward_key := _link_key(link, false)
		var reverse_key := _link_key(link, true)
		var forward_owner := _link_entry_owner(forward_key)
		var reverse_owner := _link_entry_owner(reverse_key)
		if should_exist:
			if _grid.inter_level_links.has(forward_key) or _grid.inter_level_links.has(reverse_key):
				if forward_owner != _link_owner or reverse_owner != _link_owner:
					_link_conflicts.append({
						"column_id": link.get("column_id", ""),
						"forward_owner": forward_owner,
						"reverse_owner": reverse_owner,
					})
				continue
			var cell: Vector2i = link.get("cell", INVALID_CELL)
			_grid.add_inter_level_link(
				cell,
				int(link.get("from_level", 0)),
				int(link.get("to_level", 1)),
				str(link.get("type", "ramp")),
				true
			)
			_mark_link_owned(forward_key)
			_mark_link_owned(reverse_key)
			continue
		if forward_owner == _link_owner and reverse_owner == _link_owner:
			_grid.remove_inter_level_link(
				link.get("cell", INVALID_CELL),
				int(link.get("from_level", 0)),
				int(link.get("to_level", 1))
			)
		elif forward_owner == _link_owner or reverse_owner == _link_owner:
			_link_conflicts.append({
				"column_id": link.get("column_id", ""),
				"reason": "partial_owned_link",
				"forward_owner": forward_owner,
				"reverse_owner": reverse_owner,
			})


func _mark_link_owned(key: String) -> void:
	if not _grid.inter_level_links.has(key):
		return
	var entry := (_grid.inter_level_links[key] as Dictionary).duplicate(true)
	entry["owner"] = _link_owner
	_grid.inter_level_links[key] = entry


func _link_entry_owner(key: String) -> String:
	if not _grid.inter_level_links.has(key):
		return ""
	return str((_grid.inter_level_links[key] as Dictionary).get("owner", "foreign"))


func _link_key(link: Dictionary, reverse: bool) -> String:
	var cell: Vector2i = link.get("cell", INVALID_CELL)
	var from_level := int(link.get("from_level", 0))
	var to_level := int(link.get("to_level", 1))
	if reverse:
		var swap := from_level
		from_level = to_level
		to_level = swap
	return "%d,%d,%d,%d" % [cell.x, cell.y, from_level, to_level]


func _solved_columns(record: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if _record_has_transition(record):
		return result
	var active := _fully_extended_indices(record)
	if not _active_set_is_valid(active):
		return result
	for link in _link_specs:
		var column_id := str(link.get("column_id", ""))
		if column_id.is_empty() or column_id in result:
			continue
		var modules := _modules_for_column(column_id)
		if modules.size() != active.size() or modules.size() < 2:
			continue
		var categories: Array[String] = []
		var rotten := false
		for module in modules:
			categories.append(str(module.get("category", "")))
			rotten = rotten or bool(module.get("rotten", false))
		categories.sort()
		if rotten or categories != active or not _modules_form_ascending_steps(modules):
			continue
		result.append(column_id)
	result.sort()
	return result


func _record_has_transition(record: Dictionary) -> bool:
	for index_id in get_index_ids():
		if str(_index_state_from_record(record, index_id).get("phase", "")) \
				in ["extending", "retracting"]:
			return true
	return false


func _fully_extended_indices(record: Dictionary) -> Array[String]:
	var active: Array[String] = []
	for index_id in get_index_ids():
		if str(_index_state_from_record(record, index_id).get("phase", "")) == "extended":
			active.append(index_id)
	active.sort()
	return active


func _active_set_is_valid(active: Array[String]) -> bool:
	for valid_set in _valid_active_sets:
		if valid_set == active:
			return true
	return false


func _modules_for_column(column_id: String) -> Array[Dictionary]:
	var modules: Array[Dictionary] = []
	for index_spec in _index_specs:
		for module_v in index_spec.get("drawer_modules", []) as Array:
			var module := module_v as Dictionary
			if str(module.get("column", "")) == column_id:
				modules.append(module)
	modules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("height", 0)) < int(b.get("height", 0)))
	return modules


func _modules_form_ascending_steps(modules: Array[Dictionary]) -> bool:
	var previous_depth := INF
	for module in modules:
		var closed: Vector3 = module.get("closed_position", Vector3.ZERO)
		var extended: Vector3 = module.get("extended_position", closed)
		var depth := closed.distance_to(extended)
		if depth <= 0.05 or depth >= previous_depth - 0.05:
			return false
		previous_depth = depth
	return true


func _installed_link_count() -> int:
	var count := 0
	for link in _link_specs:
		if _link_entry_owner(_link_key(link, false)) == _link_owner \
				and _link_entry_owner(_link_key(link, true)) == _link_owner:
			count += 1
	return count


func _enabled_collision_count() -> int:
	var count := 0
	for entries_v in _module_presenters.values():
		for entry_v in entries_v as Array:
			var collision := (entry_v as Dictionary).get("collision") as CollisionShape3D
			if collision != null and not collision.disabled:
				count += 1
	return count


func _normalize_index_specs(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for value_v in values:
		if not value_v is Dictionary:
			return []
		var value := (value_v as Dictionary).duplicate(true)
		var index_id := str(value.get("index_id", value.get("id", ""))).strip_edges()
		var lever_data := _as_vector3(value.get(
			"lever_data_position", value.get("lever_position", Vector3.INF)))
		var lever_render := _as_vector3(value.get("lever_render_position", lever_data))
		var modules_raw: Variant = value.get("drawer_modules", value.get("modules", []))
		if index_id.is_empty() or seen.has(index_id) or not lever_data.is_finite() \
				or not lever_render.is_finite() or not modules_raw is Array \
				or (modules_raw as Array).is_empty():
			return []
		var modules: Array[Dictionary] = []
		var fixed_depth := -1.0
		for module_v in modules_raw as Array:
			if not module_v is Dictionary:
				return []
			var module := (module_v as Dictionary).duplicate(true)
			var module_id := str(module.get("id", "")).strip_edges()
			var column := str(module.get("column", module.get("column_id", ""))).strip_edges()
			var category := str(module.get("category", index_id)).strip_edges()
			var closed := _as_vector3(module.get("closed_position", Vector3.INF))
			var extended := _as_vector3(module.get("extended_position", Vector3.INF))
			if not extended.is_finite():
				var direction := _as_vector3(module.get("extension_direction", Vector3.ZERO))
				var distance := float(module.get("extension", 0.0))
				if not direction.is_finite() or direction.length() <= 0.001 or distance <= 0.0:
					return []
				extended = closed + direction.normalized() * distance
			var collision_size := _as_vector3(module.get(
				"collision_size", Vector3(3.0, 0.65, 1.5)))
			var depth := closed.distance_to(extended)
			if module_id.is_empty() or column.is_empty() or category != index_id \
					or not closed.is_finite() or not extended.is_finite() or depth <= 0.05 \
					or not collision_size.is_finite() or collision_size.x <= 0.0 \
					or collision_size.y <= 0.0 or collision_size.z <= 0.0 \
					or int(module.get("height", -1)) < 0:
				return []
			if fixed_depth < 0.0:
				fixed_depth = depth
			elif absf(depth - fixed_depth) > 0.05:
				# One category has one authored depth even though its drawers occupy many columns.
				return []
			module["id"] = module_id
			module["column"] = column
			module["category"] = category
			module["closed_position"] = closed
			module["extended_position"] = extended
			module["collision_size"] = collision_size
			module["collision_offset"] = _as_vector3(module.get(
				"collision_offset", Vector3.ZERO))
			module["tint"] = _as_color(module.get("tint", value.get(
				"tint", Color(0.4, 0.75, 0.82))))
			modules.append(module)
		seen[index_id] = true
		value["index_id"] = index_id
		value["label"] = str(value.get("label", index_id)).strip_edges()
		value["lever_data_position"] = lever_data
		value["lever_render_position"] = lever_render
		value["drawer_modules"] = modules
		value["fixed_depth"] = fixed_depth
		value["tint"] = _as_color(value.get(
			"tint", modules[0].get("tint", Color(0.4, 0.75, 0.82))))
		result.append(value)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("index_id", "")) < str(b.get("index_id", "")))
	return result


func _normalize_active_sets(values: Variant, indices: Array[Dictionary]) -> Array[Array]:
	var result: Array[Array] = []
	if not values is Array:
		return result
	var allowed := {}
	for spec in indices:
		allowed[str(spec.get("index_id", ""))] = true
	for set_v in values as Array:
		if not set_v is Array or (set_v as Array).size() < 2:
			return []
		var normalized: Array[String] = []
		for id_v in set_v as Array:
			var index_id := str(id_v).strip_edges()
			if not allowed.has(index_id) or index_id in normalized:
				return []
			normalized.append(index_id)
		normalized.sort()
		if normalized not in result:
			result.append(normalized)
	return result


func _normalize_links(
		grid: GridWorld,
		values: Variant,
		indices: Array[Dictionary]
	) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not values is Array:
		return result
	var columns := {}
	for spec in indices:
		for module_v in spec.get("drawer_modules", []) as Array:
			columns[str((module_v as Dictionary).get("column", ""))] = true
	var seen := {}
	for value_v in values as Array:
		if not value_v is Dictionary:
			return []
		var value := value_v as Dictionary
		var column_id := str(value.get("column_id", value.get("column", ""))).strip_edges()
		var cell := _as_cell(value.get("cell", INVALID_CELL))
		var from_level := int(value.get("from_level", value.get("from", -1)))
		var to_level := int(value.get("to_level", value.get("to", -1)))
		var link_type := str(value.get("type", "ramp"))
		var identity := "%s:%d:%d:%d:%d" % [
			column_id, cell.x, cell.y, from_level, to_level]
		if column_id.is_empty() or not columns.has(column_id) or seen.has(identity) \
				or cell == INVALID_CELL or not grid.is_in_bounds(cell.x, cell.y) \
				or grid.get_tile(cell.x, cell.y) == GridWorld.Tile.WALL \
				or from_level < 0 or to_level < 0 or from_level >= grid.level_count \
				or to_level >= grid.level_count or from_level == to_level \
				or not grid.is_cell_allowed_on_level(cell, from_level) \
				or not grid.is_cell_allowed_on_level(cell, to_level) \
				or not link_type in ["ramp", "ladder"] \
				or not bool(value.get("bidirectional", true)):
			return []
		seen[identity] = true
		result.append({
			"column_id": column_id,
			"cell": cell,
			"from_level": from_level,
			"to_level": to_level,
			"type": link_type,
			"bidirectional": true,
		})
	return result


func _normalize_cells(grid: GridWorld, values: Variant, allow_empty: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not values is Array:
		return result
	for value in values as Array:
		var cell := _as_cell(value)
		if cell == INVALID_CELL or not grid.is_in_bounds(cell.x, cell.y) \
				or grid.get_tile(cell.x, cell.y) == GridWorld.Tile.WALL:
			return []
		if cell not in result:
			result.append(cell)
	if not allow_empty and result.is_empty():
		return []
	return result


func _validate_closed_topology(
		grid: GridWorld,
		blocker_cells: Array[Vector2i],
		blocker_tag: String,
		links: Array[Dictionary]
	) -> bool:
	for cell in blocker_cells:
		var existing := str(grid.dynamic_blockers.get(cell, ""))
		if not existing.is_empty() and existing != blocker_tag:
			return false
	for link in links:
		if grid.inter_level_links.has(_link_key_static(link, false)) \
				or grid.inter_level_links.has(_link_key_static(link, true)):
			return false
	return true


func _cells_from_values(values: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not values is Array:
		return result
	for value in values as Array:
		var cell := _as_cell(value)
		if cell != INVALID_CELL and cell not in result:
			result.append(cell)
	return result


func _as_cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int((value as Vector2).x), int((value as Vector2).y))
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return INVALID_CELL


func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		return Vector3(
			float((value as Array)[0]),
			float((value as Array)[1]),
			float((value as Array)[2])
		)
	return Vector3.INF


func _as_color(value: Variant) -> Color:
	if value is Color:
		return value
	if value is Array and (value as Array).size() >= 3:
		return Color(
			float((value as Array)[0]),
			float((value as Array)[1]),
			float((value as Array)[2]),
			float((value as Array)[3]) if (value as Array).size() >= 4 else 1.0
		)
	return Color.WHITE


func _fit_drawer_visual(visual: MeshInstance3D, spec: Dictionary) -> void:
	var target_size: Vector3 = _as_vector3(spec.get(
		"visual_scale", spec.get("collision_size", Vector3(3.0, 0.65, 1.5))))
	if not target_size.is_finite() or target_size.x <= 0.0 \
			or target_size.y <= 0.0 or target_size.z <= 0.0:
		target_size = spec.get("collision_size", Vector3(3.0, 0.65, 1.5))
	var bounds := ArchiveDrawerMesh.get_aabb()
	var source_size := bounds.size
	visual.scale = Vector3(
		target_size.x / maxf(0.001, source_size.x),
		target_size.y / maxf(0.001, source_size.y),
		target_size.z / maxf(0.001, source_size.z)
	)
	visual.position = -bounds.get_center() * visual.scale


func _apply_module_material(visual: MeshInstance3D, spec: Dictionary) -> void:
	var source := ArchiveDrawerMesh.surface_get_material(0)
	if not source is BaseMaterial3D:
		return
	var material := (source as BaseMaterial3D).duplicate() as BaseMaterial3D
	var tint := _as_color(spec.get("tint", Color.WHITE))
	if bool(spec.get("rotten", false)):
		tint = tint.darkened(0.48)
		material.roughness = 0.92
	material.albedo_color *= tint
	visual.material_override = material


static func _link_key_static(link: Dictionary, reverse: bool) -> String:
	var cell_v: Variant = link.get("cell", INVALID_CELL)
	var cell := cell_v as Vector2i if cell_v is Vector2i else INVALID_CELL
	var from_level := int(link.get("from_level", 0))
	var to_level := int(link.get("to_level", 1))
	if reverse:
		var swap := from_level
		from_level = to_level
		to_level = swap
	return "%d,%d,%d,%d" % [cell.x, cell.y, from_level, to_level]


func _exit_tree() -> void:
	_cancel_all_transition_tags()
