class_name SpoofAccessReceiver
extends Node3D

## Save-authoritative access gate opened by Aster spoofing his own tracked location.
##
## TypedTerminal owns the physical interaction and consumed receipt. This receiver accepts only
## the exact live credential/authorize command, commits access before changing navigation, and
## derives the gate collision and presentation from GameState on every restore.
## The built-in gate is an explicit temporary blockout pending an external UV-mapped asset.

signal access_authorized(access_id: String, state: Dictionary)
signal authority_rejected(reason: String)

const STATE_CONTRACT := "spoof_access_receiver/v1"
const AUTHORITY_VERSION := 1
const AUTHORITY_PREFIX := "gameplay:spoof_access_receiver:"
const TERMINAL_CONTRACT := "typed_terminal/v1"
const TERMINAL_ID_PREFIX := "typed_terminal:"
const TERMINAL_KEY_PREFIX := "gameplay:typed_terminal:"
const EXPECTED_FAMILY := "terminal"
const EXPECTED_SUBTYPE := "credential"
const EXPECTED_EFFECT := "authorize"
const PHASE_LOCKED := "location_mismatch"
const PHASE_AUTHORIZED := "tracked_access_authorized"
const POSITION_EPSILON := 0.05
const TICK_EPSILON := 0.000001

var _game_state: GameState
var _access_id := ""
var _blocker_cells: Array[Vector2i] = []
var _blocker_tag := ""
var _phase := PHASE_LOCKED
var _accepted_tick := -1.0
var _receipt_provenance: Dictionary = {}
var _configured := false
var _restoring := false
var _last_restore_valid := true
var _gate_root: Node3D
var _gate_collision: CollisionShape3D
var _status: Label3D


func configure(
		game_state: GameState,
		access_id: String,
		world_position: Vector3,
		blocker_cells: Array,
		options := {}
	) -> bool:
	var normalized_id := access_id.strip_edges()
	if _configured or game_state == null or game_state.grid == null \
			or normalized_id.is_empty() or blocker_cells.is_empty():
		return false
	_game_state = game_state
	_access_id = normalized_id
	_blocker_tag = "spoof_access_%s" % _access_id
	for raw_cell in blocker_cells:
		var cell := _decode_cell(raw_cell)
		if cell == Vector2i(-1, -1) or not _game_state.grid.is_in_bounds(cell.x, cell.y):
			return false
		if not _blocker_cells.has(cell):
			_blocker_cells.append(cell)
	position = world_position
	name = "SpoofAccess_%s" % _access_id
	_build_visual(options as Dictionary)
	_configured = true
	return sync_from_game_state()


func authority_state_key() -> String:
	return AUTHORITY_PREFIX + _access_id if not _access_id.is_empty() else ""


func can_accept_terminal_command(command: Dictionary) -> bool:
	if not _configured or not _last_restore_valid or _phase != PHASE_LOCKED:
		return false
	var normalized := _normalize_command(command)
	return not normalized.is_empty() and _live_source_matches(normalized)


func accept_terminal_command(command: Dictionary) -> bool:
	if not can_accept_terminal_command(command):
		return false
	var receipt := _normalize_command(command)
	_phase = PHASE_AUTHORIZED
	_accepted_tick = float(receipt.get("accepted_tick", -1.0))
	_receipt_provenance = receipt.duplicate(true)
	_receipt_provenance["source_contract"] = TERMINAL_CONTRACT
	_publish_state()
	_apply_presenter()
	access_authorized.emit(_access_id, get_state())
	return true


func is_authorized() -> bool:
	return _phase == PHASE_AUTHORIZED


func get_state() -> Dictionary:
	return {
		"contract": STATE_CONTRACT,
		"version": AUTHORITY_VERSION,
		"access_id": _access_id,
		"phase": _phase,
		"accepted_tick": _accepted_tick,
		"receipt_provenance": _receipt_provenance.duplicate(true),
		"blocker_cells": _encode_cells(),
		"blocker_tag": _blocker_tag,
		"configured": _configured,
		"last_restore_valid": _last_restore_valid,
	}


func reset_access(reason: StringName = &"access_reset") -> bool:
	if not _configured:
		return false
	_phase = PHASE_LOCKED
	_accepted_tick = -1.0
	_receipt_provenance.clear()
	_game_state.set_world_state(authority_state_key(), {
		"contract": STATE_CONTRACT,
		"version": AUTHORITY_VERSION,
		"access_id": _access_id,
		"phase": PHASE_LOCKED,
		"accepted_tick": -1.0,
		"receipt_provenance": {},
		"blocker_cells": _encode_cells(),
		"blocker_tag": _blocker_tag,
		"reset_reason": str(reason),
	})
	_apply_presenter()
	return true


func on_game_state_snapshot_restored() -> bool:
	return sync_from_game_state()


func sync_from_game_state() -> bool:
	if not _configured or _game_state == null:
		_last_restore_valid = false
		return false
	var raw: Variant = _game_state.get_world_state(authority_state_key(), {})
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		var saved := raw as Dictionary
		if not _valid_state(saved):
			_last_restore_valid = false
			authority_rejected.emit("invalid_saved_authority")
			return false
		_restore_state(saved)
		_last_restore_valid = true
		return true
	_phase = PHASE_LOCKED
	_accepted_tick = -1.0
	_receipt_provenance.clear()
	_apply_presenter()
	_publish_state()
	_last_restore_valid = true
	return true


func _restore_state(saved: Dictionary) -> void:
	_restoring = true
	_phase = str(saved.get("phase", PHASE_LOCKED))
	_accepted_tick = float(saved.get("accepted_tick", -1.0))
	_receipt_provenance = (
		(saved.get("receipt_provenance", {}) as Dictionary).duplicate(true)
	)
	_apply_presenter()
	_restoring = false


func _publish_state() -> void:
	if _restoring or not _configured or _game_state == null:
		return
	_game_state.set_world_state(authority_state_key(), get_state())


func _valid_state(saved: Dictionary) -> bool:
	if str(saved.get("contract", "")) != STATE_CONTRACT \
			or int(saved.get("version", 0)) != AUTHORITY_VERSION \
			or str(saved.get("access_id", "")) != _access_id \
			or str(saved.get("blocker_tag", "")) != _blocker_tag:
		return false
	var saved_cells := _decode_cells(saved.get("blocker_cells", null))
	if saved_cells != _blocker_cells:
		return false
	var phase := str(saved.get("phase", ""))
	if phase == PHASE_LOCKED:
		return float(saved.get("accepted_tick", -1.0)) < 0.0 \
			and (saved.get("receipt_provenance", {}) as Dictionary).is_empty()
	if phase != PHASE_AUTHORIZED:
		return false
	var provenance_v: Variant = saved.get("receipt_provenance", null)
	if not provenance_v is Dictionary:
		return false
	var provenance := provenance_v as Dictionary
	var normalized := _normalize_command(provenance)
	return not normalized.is_empty() \
		and str(provenance.get("source_contract", "")) == TERMINAL_CONTRACT \
		and is_equal_approx(
			float(saved.get("accepted_tick", -1.0)),
			float(normalized.get("accepted_tick", -2.0))
		)


func _normalize_command(command: Dictionary) -> Dictionary:
	if str(command.get("family", "")) != EXPECTED_FAMILY \
			or str(command.get("subtype", "")) != EXPECTED_SUBTYPE \
			or str(command.get("effect", "")) != EXPECTED_EFFECT:
		return {}
	var source_id := str(command.get("source_id", ""))
	var source_key := str(command.get("source_authority_key", ""))
	var actor := str(command.get("actor", ""))
	var trigger_count := int(command.get("source_trigger_count", 0))
	var source_position := _vector(command.get("source_position", []))
	var accepted_tick := float(command.get("accepted_tick", -1.0))
	if not source_id.begins_with(TERMINAL_ID_PREFIX) \
			or source_id.length() <= TERMINAL_ID_PREFIX.length():
		return {}
	var stable_id := source_id.trim_prefix(TERMINAL_ID_PREFIX)
	if source_key != TERMINAL_KEY_PREFIX + stable_id \
			or actor.is_empty() or trigger_count <= 0 \
			or not source_position.is_finite() \
			or not is_finite(accepted_tick) or accepted_tick < 0.0:
		return {}
	return {
		"family": EXPECTED_FAMILY,
		"subtype": EXPECTED_SUBTYPE,
		"effect": EXPECTED_EFFECT,
		"source_id": source_id,
		"source_authority_key": source_key,
		"source_trigger_count": trigger_count,
		"actor": actor,
		"source_position": [source_position.x, source_position.y, source_position.z],
		"accepted_tick": accepted_tick,
	}


func _live_source_matches(command: Dictionary) -> bool:
	var actor := str(command.get("actor", ""))
	var source_id := str(command.get("source_id", ""))
	if not _game_state.characters.has(actor) or not _game_state.has_interactable(source_id):
		return false
	var source := _game_state.get_interactable(source_id)
	if not bool(source.get("one_shot", false)) \
			or not bool(source.get("triggered", false)) \
			or bool(source.get("enabled", true)) \
			or int(source.get("trigger_count", 0)) \
				!= int(command.get("source_trigger_count", -1)) \
			or str(source.get("last_trigger_character", "")) != actor:
		return false
	var source_pos := _vector(command.get("source_position", []))
	var registered_pos := _vector(source.get("position", Vector3(INF, INF, INF)))
	if source_pos.distance_to(registered_pos) > POSITION_EPSILON:
		return false
	var radius := maxf(0.0, float(source.get("radius", 0.0)))
	if _game_state.get_position(actor).distance_to(registered_pos) > radius + POSITION_EPSILON:
		return false
	if _game_state.scheduler == null:
		return false
	var now := float(_game_state.scheduler.get_current_tick())
	return absf(float(command.get("accepted_tick", -1.0)) - now) <= TICK_EPSILON \
		and _source_authority_matches(command)


func _source_authority_matches(command: Dictionary) -> bool:
	var value: Variant = _game_state.get_world_state(
		str(command.get("source_authority_key", "")), {})
	if not value is Dictionary:
		return false
	var source := value as Dictionary
	if str(source.get("contract", "")) != TERMINAL_CONTRACT:
		return false
	var receipt_v: Variant = source.get("command", null)
	if not receipt_v is Dictionary:
		return false
	var normalized := _normalize_command(receipt_v as Dictionary)
	return not normalized.is_empty() and normalized == command


func _apply_presenter() -> void:
	var authorized := _phase == PHASE_AUTHORIZED
	if _game_state != null and _game_state.grid != null:
		for cell in _blocker_cells:
			var owner := str(_game_state.grid.dynamic_blockers.get(cell, ""))
			if authorized:
				if owner == _blocker_tag:
					_game_state.grid.remove_dynamic_blocker(cell)
			elif owner.is_empty() or owner == _blocker_tag:
				_game_state.grid.add_dynamic_blocker(cell, _blocker_tag)
	if is_instance_valid(_gate_root):
		_gate_root.visible = not authorized
	if is_instance_valid(_gate_collision):
		_gate_collision.disabled = authorized
	if is_instance_valid(_status):
		_status.text = (
			"TRACKED ACCESS // AUTHORIZED"
			if authorized else "REPORTED LOCATION // MISMATCH"
		)
		_status.modulate = (
			Color(0.38, 0.92, 0.66) if authorized else Color(0.98, 0.34, 0.22)
		)


func _build_visual(options: Dictionary) -> void:
	_status = Label3D.new()
	_status.name = "AccessStatus"
	_status.position = Vector3(0.0, 2.35, 0.0)
	_status.font_size = 28
	_status.pixel_size = 0.006
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.no_depth_test = true
	_status.set_meta("camera_occlusion_exempt", true)
	add_child(_status)

	_gate_root = Node3D.new()
	_gate_root.name = "TrackedAccessGate"
	_gate_root.set_meta("asset_authoring_status", "temporary_blockout")
	add_child(_gate_root)
	var gate_size: Vector3 = options.get("gate_size", Vector3(7.0, 3.2, 0.45))
	var gate_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = gate_size
	gate_mesh.mesh = mesh
	gate_mesh.position = Vector3(0.0, gate_size.y * 0.5, 0.0)
	gate_mesh.material_override = _material(
		Color(0.08, 0.055, 0.045), Color(0.94, 0.22, 0.12), 0.72)
	_gate_root.add_child(gate_mesh)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_gate_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = gate_size
	_gate_collision.shape = shape
	_gate_collision.position = Vector3(0.0, gate_size.y * 0.5, 0.0)
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


func _vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() >= 3:
		return Vector3(
			float((value as Array)[0]),
			float((value as Array)[1]),
			float((value as Array)[2])
		)
	return Vector3(INF, INF, INF)


func _decode_cell(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw as Vector2i
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2i(int((raw as Array)[0]), int((raw as Array)[1]))
	return Vector2i(-1, -1)


func _decode_cells(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not value is Array:
		return result
	for raw_cell in value as Array:
		var cell := _decode_cell(raw_cell)
		if cell == Vector2i(-1, -1):
			return []
		result.append(cell)
	return result


func _encode_cells() -> Array:
	var result: Array = []
	for cell in _blocker_cells:
		result.append([cell.x, cell.y])
	return result
