class_name EmpCutoffCircuit
extends Node3D

## Permanent fail-open archive cut-off triggered by Aster's canonical EMP pulse.
##
## EMP is the intervention; this circuit owns the consequence. It commits the power-cut state
## immediately, removes its authored grid blockers, and derives collision/visuals from GameState.

signal power_cut_committed(circuit_id: String, state: Dictionary)

const STATE_CONTRACT := "emp_cutoff_circuit/v1"
const STATE_VERSION := 1
const AUTHORITY_PREFIX := "gameplay:emp_cutoff_circuit:"
const PHASE_FAULTED := "faulted_closed"
const PHASE_CUT := "power_cut_open"

var _game_state: GameState
var _circuit_id := ""
var _blocker_cells: Array[Vector2i] = []
var _blocker_tag := ""
var _phase := PHASE_FAULTED
var _commit_tick := -1.0
var _configured := false
var _restoring := false
var _housing: MeshInstance3D
var _display: MeshInstance3D
var _gate_root: Node3D
var _gate_collision: CollisionShape3D
var _status: Label3D


func configure(
		game_state: GameState,
		circuit_id: String,
		world_position: Vector3,
		blocker_cells: Array,
		options := {}
	) -> bool:
	var normalized_id := circuit_id.strip_edges()
	if _configured or game_state == null or game_state.grid == null \
			or normalized_id.is_empty():
		return false
	_game_state = game_state
	_circuit_id = normalized_id
	_blocker_tag = "emp_cutoff_%s" % _circuit_id
	for raw_cell in blocker_cells:
		var cell := _decode_cell(raw_cell)
		if cell == Vector2i(-1, -1) or not _game_state.grid.is_in_bounds(cell.x, cell.y):
			return false
		if not _blocker_cells.has(cell):
			_blocker_cells.append(cell)
	position = world_position
	name = "EmpCutoff_%s" % _circuit_id
	_build_visual(options as Dictionary)
	_configured = true
	var raw_saved: Variant = _game_state.get_world_state(authority_state_key(), {})
	if raw_saved is Dictionary and _valid_state(raw_saved as Dictionary):
		_restore_state(raw_saved as Dictionary)
	else:
		_phase = PHASE_FAULTED
		_commit_tick = -1.0
		_apply_presenter()
		_publish_state()
	return true


func authority_state_key() -> String:
	return AUTHORITY_PREFIX + _circuit_id if not _circuit_id.is_empty() else ""


func apply_emp(duration: float) -> bool:
	if not _configured or duration <= 0.0 or _phase != PHASE_FAULTED:
		return false
	_phase = PHASE_CUT
	_commit_tick = _scheduler_tick()
	_apply_presenter()
	_publish_state()
	power_cut_committed.emit(_circuit_id, get_state())
	return true


func get_state() -> Dictionary:
	return {
		"contract": STATE_CONTRACT,
		"version": STATE_VERSION,
		"circuit_id": _circuit_id,
		"phase": _phase,
		"commit_tick": _commit_tick,
		"blocker_cells": _encode_cells(),
		"blocker_tag": _blocker_tag,
		"configured": _configured,
	}


## Preview/checkpoint reset only. The in-world EMP consequence remains permanent once committed.
func reset(_reason: StringName = &"emp_cutoff_reset") -> bool:
	if not _configured or _game_state == null:
		return false
	_phase = PHASE_FAULTED
	_commit_tick = -1.0
	_apply_presenter()
	_publish_state()
	return true


func on_game_state_snapshot_restored() -> void:
	if not _configured or _game_state == null:
		return
	var raw_saved: Variant = _game_state.get_world_state(authority_state_key(), {})
	if raw_saved is Dictionary and _valid_state(raw_saved as Dictionary):
		_restore_state(raw_saved as Dictionary)
		return
	_phase = PHASE_FAULTED
	_commit_tick = -1.0
	_apply_presenter()
	_publish_state()


func _restore_state(saved: Dictionary) -> void:
	_restoring = true
	_phase = str(saved.get("phase", PHASE_FAULTED))
	_commit_tick = float(saved.get("commit_tick", -1.0))
	_apply_presenter()
	_restoring = false


func _publish_state() -> void:
	if _restoring or not _configured or _game_state == null:
		return
	_game_state.set_world_state(authority_state_key(), get_state())


func _valid_state(saved: Dictionary) -> bool:
	if str(saved.get("contract", "")) != STATE_CONTRACT \
			or int(saved.get("version", 0)) != STATE_VERSION \
			or str(saved.get("circuit_id", "")) != _circuit_id:
		return false
	var phase := str(saved.get("phase", ""))
	var tick := float(saved.get("commit_tick", -1.0))
	if phase == PHASE_FAULTED:
		return tick < 0.0
	if phase != PHASE_CUT or not is_finite(tick) or tick < 0.0:
		return false
	var cells_v: Variant = saved.get("blocker_cells", null)
	if not cells_v is Array:
		return false
	var saved_cells: Array[Vector2i] = []
	for raw_cell in cells_v as Array:
		var cell := _decode_cell(raw_cell)
		if cell == Vector2i(-1, -1):
			return false
		saved_cells.append(cell)
	return saved_cells == _blocker_cells \
		and str(saved.get("blocker_tag", "")) == _blocker_tag


func _apply_presenter() -> void:
	if not _configured and _game_state == null:
		return
	var opened := _phase == PHASE_CUT
	if _game_state != null and _game_state.grid != null:
		for cell in _blocker_cells:
			var owner := str(_game_state.grid.dynamic_blockers.get(cell, ""))
			if opened:
				if owner == _blocker_tag:
					_game_state.grid.remove_dynamic_blocker(cell)
			elif owner.is_empty() or owner == _blocker_tag:
				_game_state.grid.add_dynamic_blocker(cell, _blocker_tag)
	if is_instance_valid(_gate_root):
		_gate_root.visible = not opened
	if is_instance_valid(_gate_collision):
		_gate_collision.disabled = opened
	if is_instance_valid(_display):
		var material := _display.material_override as StandardMaterial3D
		if material != null:
			var color := Color(0.24, 0.86, 0.70) if opened else Color(0.96, 0.34, 0.15)
			material.albedo_color = color.darkened(0.66)
			material.emission = color
	if is_instance_valid(_status):
		_status.text = "POWER CUT // ROUTE OPEN" if opened else "FAULTED CIRCUIT // EMP"
		_status.modulate = Color(0.36, 0.92, 0.74) if opened else Color(1.0, 0.48, 0.24)


func _build_visual(options: Dictionary) -> void:
	_housing = MeshInstance3D.new()
	_housing.name = "CircuitHousing"
	var housing_mesh := BoxMesh.new()
	housing_mesh.size = Vector3(1.4, 1.7, 0.9)
	_housing.mesh = housing_mesh
	_housing.position = Vector3(0.0, 0.85, 0.0)
	_housing.material_override = _material(
		Color(0.035, 0.045, 0.048), Color(0.14, 0.26, 0.27), 0.25)
	add_child(_housing)

	_display = MeshInstance3D.new()
	_display.name = "FaultDisplay"
	var display_mesh := BoxMesh.new()
	display_mesh.size = Vector3(0.92, 0.52, 0.08)
	_display.mesh = display_mesh
	_display.position = Vector3(0.0, 1.05, 0.49)
	_display.material_override = _material(
		Color(0.26, 0.04, 0.02), Color(0.96, 0.34, 0.15), 2.2)
	add_child(_display)

	_status = Label3D.new()
	_status.name = "CircuitStatus"
	_status.position = Vector3(0.0, 2.05, 0.0)
	_status.font_size = 28
	_status.pixel_size = 0.006
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.no_depth_test = true
	_status.set_meta("camera_occlusion_exempt", true)
	add_child(_status)

	_gate_root = Node3D.new()
	_gate_root.name = "FaultedGate"
	var gate_position: Vector3 = options.get(
		"gate_local_position", Vector3(-8.0, 1.6, -13.5))
	var gate_size: Vector3 = options.get("gate_size", Vector3(0.55, 3.2, 3.2))
	_gate_root.position = gate_position
	add_child(_gate_root)
	var gate_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = gate_size
	gate_mesh.mesh = mesh
	gate_mesh.material_override = _material(
		Color(0.07, 0.075, 0.078), Color(0.94, 0.18, 0.08), 0.8)
	_gate_root.add_child(gate_mesh)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_gate_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = gate_size
	_gate_collision.shape = shape
	body.add_child(_gate_collision)
	_gate_root.add_child(body)


func _material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.72
	material.emission_enabled = energy > 0.0
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material


func _decode_cell(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw as Vector2i
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
	return Vector2i(-1, -1)


func _encode_cells() -> Array:
	var result: Array = []
	for cell in _blocker_cells:
		result.append([cell.x, cell.y])
	return result


func _scheduler_tick() -> float:
	if _game_state != null and _game_state.scheduler != null:
		return float(_game_state.scheduler.get_current_tick())
	return 0.0
