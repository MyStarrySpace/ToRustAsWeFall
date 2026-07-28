class_name IronPurgeReceiver
extends Node3D

## Save-authoritative receiver for an Open Files sacrificial-iron purge.
##
## TypedTerminal owns the physical one-shot interaction. This receiver accepts only that terminal's
## exact spent signal/lure receipt, commits and presents the exposed iron fixture, and only then
## asks bound Enemy presenters to follow it through Enemy.lure_to(). A target that is attacking,
## unavailable, not yet activated, or late-bound remains pending and is retried deterministically.
##
## The built-in boxes are an explicitly marked temporary blockout. This script remains the
## gameplay/collision wrapper when the fixture receives its external UV-mapped model and texture.

signal fixture_exposed_committed(state: Dictionary)
signal target_lured(char_id: String, state: Dictionary)
signal target_lure_pending(char_id: String, availability: String)
signal authority_rejected(reason: String)

const STATE_CONTRACT := "iron_purge_receiver/v1"
const AUTHORITY_VERSION := 1
const AUTHORITY_PREFIX := "gameplay:iron_purge_receiver:"
const TERMINAL_CONTRACT := "typed_terminal/v1"
const TERMINAL_AUTHORITY_VERSION := 1
const TERMINAL_ID_PREFIX := "typed_terminal:"
const TERMINAL_KEY_PREFIX := "gameplay:typed_terminal:"
const ENEMY_KEY_PREFIX := "runtime:enemy:"

const EXPECTED_FAMILY := "terminal"
const EXPECTED_SUBTYPE := "signal"
const EXPECTED_EFFECT := "lure"
const EXPECTED_ACTOR := "aster"

const PHASE_RETRACTED := "fixture_retracted"
const PHASE_EXPOSED := "fixture_exposed"
const TARGET_DORMANT := "dormant"
const TARGET_PENDING := "pending"
const TARGET_APPLYING := "applying"
const TARGET_APPLIED := "applied"
const TARGET_DEAD := "dead"
const TARGET_PHASES := [
	TARGET_DORMANT,
	TARGET_PENDING,
	TARGET_APPLYING,
	TARGET_APPLIED,
	TARGET_DEAD,
]

const POSITION_EPSILON := 0.05
const TICK_EPSILON := 0.000001
const RESTORE_RETRY_DELAY := 0.001
const RECONCILE_RETRY_DELAY := 0.10
const FIXTURE_VISUAL_STATUS := "temporary_blockout"

var _game_state: GameState
var _receiver_id := ""
var _source_terminal_stable_id := ""
var _target_ids: Array[String] = []
var _enemies: Dictionary = {}
var _fixture_retracted_position := Vector3.ZERO
var _fixture_exposed_position := Vector3.ZERO
var _fixture_size := Vector3.ONE
var _lure_duration := 20.0
var _configured := false
var _last_restore_valid := true
var _retry_generation := 0

var _housing: MeshInstance3D
var _fixture_root: Node3D
var _fixture_mesh: MeshInstance3D
var _fixture_collision: CollisionShape3D
var _status_label: Label3D


## `source_terminal_stable_id` is the TypedTerminal stable id without its registry prefix.
func configure(
		game_state: GameState,
		receiver_id: String,
		source_terminal_stable_id: String,
		fixture_retracted_position: Vector3,
		fixture_exposed_position: Vector3,
		fixture_size: Vector3,
		target_char_ids: Array,
		lure_duration := 20.0
	) -> bool:
	var normalized_receiver_id := receiver_id.strip_edges()
	var normalized_source_id := source_terminal_stable_id.strip_edges()
	var normalized_targets := _normalize_target_ids(target_char_ids)
	if _configured or game_state == null or game_state.scheduler == null \
			or not game_state.has_method("get_world_state") \
			or not game_state.has_method("set_world_state") \
			or not game_state.scheduler.has_method("schedule_at") \
			or not game_state.scheduler.has_method("cancel_tag") \
			or normalized_receiver_id.is_empty() or normalized_source_id.is_empty() \
			or normalized_source_id.begins_with(TERMINAL_ID_PREFIX) \
			or normalized_targets.is_empty() \
			or not fixture_retracted_position.is_finite() \
			or not fixture_exposed_position.is_finite() \
			or fixture_retracted_position.distance_to(fixture_exposed_position) \
				<= POSITION_EPSILON \
			or not _valid_size(fixture_size) or lure_duration <= 0.0:
		return false
	_game_state = game_state
	_receiver_id = normalized_receiver_id
	_source_terminal_stable_id = normalized_source_id
	_target_ids = normalized_targets
	_fixture_retracted_position = fixture_retracted_position
	_fixture_exposed_position = fixture_exposed_position
	_fixture_size = fixture_size
	_lure_duration = lure_duration
	position = _fixture_retracted_position
	name = "IronPurgeReceiver_%s" % _receiver_id
	_build_fixture_visual()
	_configured = true
	return sync_from_game_state()


## Bind only an authored target, identified by Enemy.char_id. Exposed authority immediately repairs
## a late-bound target when its FSM is ready, or leaves a deterministic retry pending.
func bind_enemy(enemy: Enemy) -> bool:
	if not _configured or enemy == null or not is_instance_valid(enemy):
		return false
	var enemy_id := str(enemy.char_id).strip_edges()
	if enemy_id.is_empty() or not _target_ids.has(enemy_id):
		return false
	if enemy.game_state != null and enemy.game_state != _game_state:
		return false
	_enemies[enemy_id] = enemy
	var saved := _saved_authority()
	if _valid_exposed_authority(saved):
		_reconcile_target(enemy_id, true)
		_arm_reconcile_retry(RECONCILE_RETRY_DELAY)
	return true


func unbind_enemy(char_id: String) -> void:
	_enemies.erase(char_id)
	_arm_reconcile_retry(RECONCILE_RETRY_DELAY)


func authority_state_key() -> String:
	return AUTHORITY_PREFIX + _receiver_id if not _receiver_id.is_empty() else ""


func expected_terminal_source_id() -> String:
	return (
		TERMINAL_ID_PREFIX + _source_terminal_stable_id
		if not _source_terminal_stable_id.is_empty()
		else ""
	)


func expected_terminal_authority_key() -> String:
	return (
		TERMINAL_KEY_PREFIX + _source_terminal_stable_id
		if not _source_terminal_stable_id.is_empty()
		else ""
	)


## Pure preflight: no fixture, enemy, or receipt state changes occur here.
func can_accept_terminal_command(command: Dictionary) -> bool:
	if not _configured or not _last_restore_valid or not _authority_allows_command():
		return false
	var normalized := _normalize_command(command)
	return not normalized.is_empty() and _live_source_matches(normalized)


## Sole activation entry point. Fixture authority and its physical presenter commit before the first
## Enemy API call, so a signal-time save can always reconstruct the lure source.
func accept_terminal_command(command: Dictionary) -> bool:
	if not can_accept_terminal_command(command):
		return false
	var receipt := _normalize_command(command)
	var record := _exposed_authority(receipt)
	_game_state.set_world_state(authority_state_key(), record)
	_apply_fixture_presenter(PHASE_EXPOSED)
	fixture_exposed_committed.emit(get_state())
	reconcile_targets(true)
	return true


func sync_from_game_state() -> bool:
	_cancel_reconcile_retry()
	if not _configured or _game_state == null:
		_last_restore_valid = false
		return false
	var saved := _saved_authority()
	if saved.is_empty():
		_last_restore_valid = true
		_apply_fixture_presenter(PHASE_RETRACTED)
		_game_state.set_world_state(authority_state_key(), _retracted_authority())
		return true
	if _valid_retracted_authority(saved):
		_last_restore_valid = true
		_apply_fixture_presenter(PHASE_RETRACTED)
		return true
	if not _valid_exposed_authority(saved):
		_last_restore_valid = false
		_apply_fixture_presenter(PHASE_RETRACTED)
		authority_rejected.emit("invalid_saved_authority")
		return false
	_last_restore_valid = true
	# The physical cause is reconstructed before any interrupted target handoff is examined.
	_apply_fixture_presenter(PHASE_EXPOSED)
	_repair_interrupted_target_receipts()
	_arm_restored_reconcile_retry()
	return true


func on_game_state_snapshot_restored() -> bool:
	return sync_from_game_state()


## Reconcile only an already-committed exposed fixture. This cannot manufacture terminal authority.
func reconcile_targets(emit_signals := false) -> bool:
	var saved := _saved_authority()
	if not _configured or not _valid_exposed_authority(saved):
		_cancel_reconcile_retry()
		return false
	_repair_interrupted_target_receipts()
	var complete := true
	for enemy_id in _target_ids:
		var receipt := _target_receipt(_saved_authority(), enemy_id)
		var status := str(receipt.get("status", TARGET_PENDING))
		if status in [TARGET_APPLIED, TARGET_DEAD]:
			continue
		if not _reconcile_target(enemy_id, emit_signals):
			complete = false
	_arm_reconcile_retry(RECONCILE_RETRY_DELAY)
	return complete


func is_fixture_exposed() -> bool:
	return _valid_exposed_authority(_saved_authority())


func get_fixture_visual() -> Node3D:
	return _fixture_root


## Preview/checkpoint reset only. Gameplay terminals remain one-shot and expose no retract verb.
func reset(reason: StringName = &"iron_purge_reset") -> bool:
	if not _configured or _game_state == null:
		return false
	_cancel_reconcile_retry()
	var record := _retracted_authority()
	record["reset_reason"] = str(reason)
	record["reset_tick"] = _scheduler_tick()
	_game_state.set_world_state(authority_state_key(), record)
	_apply_fixture_presenter(PHASE_RETRACTED)
	_last_restore_valid = true
	return true


func get_state() -> Dictionary:
	var saved := _saved_authority()
	var phase := "invalid_authority"
	if saved.is_empty():
		phase = "unconfigured" if not _configured else "missing_authority"
	elif _valid_retracted_authority(saved):
		phase = PHASE_RETRACTED
	elif _valid_exposed_authority(saved):
		phase = PHASE_EXPOSED
	return {
		"contract": STATE_CONTRACT,
		"version": AUTHORITY_VERSION,
		"configured": _configured,
		"receiver_id": _receiver_id,
		"authority_key": authority_state_key(),
		"phase": phase,
		"source_terminal_id": expected_terminal_source_id(),
		"fixture_retracted_position": _vector_data(_fixture_retracted_position),
		"fixture_exposed_position": _vector_data(_fixture_exposed_position),
		"fixture_presenter_position": (
			_vector_data(_fixture_root.global_position)
			if is_instance_valid(_fixture_root)
			else []
		),
		"fixture_size": _vector_data(_fixture_size),
		"fixture_visual_status": FIXTURE_VISUAL_STATUS,
		"lure_duration": _lure_duration,
		"next_reconcile_deadline": (
			float(saved.get("next_reconcile_deadline", -1.0))
			if _valid_exposed_authority(saved)
			else -1.0
		),
		"target_receipts": (
			(saved.get("target_receipts", []) as Array).duplicate(true)
			if _valid_exposed_authority(saved) or _valid_retracted_authority(saved)
			else []
		),
		"receipt_provenance": (
			(saved.get("receipt_provenance", {}) as Dictionary).duplicate(true)
			if _valid_exposed_authority(saved)
			else {}
		),
		"bound_enemy_ids": _bound_enemy_ids(),
		"last_restore_valid": _last_restore_valid,
	}


func get_mechanism_spec() -> Dictionary:
	return {
		"family": "terminal_receiver",
		"subtype": EXPECTED_SUBTYPE,
		"effect": EXPECTED_EFFECT,
		"owner_character": EXPECTED_ACTOR,
		"state_contract": STATE_CONTRACT,
		"authority_key": authority_state_key(),
		"source_terminal_id": expected_terminal_source_id(),
		"target_ids": _target_ids.duplicate(),
		"fixture_visual_status": FIXTURE_VISUAL_STATUS,
	}


func _normalize_command(command: Dictionary) -> Dictionary:
	if str(command.get("family", "")) != EXPECTED_FAMILY \
			or str(command.get("subtype", "")) != EXPECTED_SUBTYPE \
			or str(command.get("effect", "")) != EXPECTED_EFFECT \
			or str(command.get("actor", "")) != EXPECTED_ACTOR \
			or str(command.get("source_id", "")) != expected_terminal_source_id() \
			or str(command.get("source_authority_key", "")) \
				!= expected_terminal_authority_key():
		return {}
	var trigger_count := int(command.get("source_trigger_count", 0))
	var source_position := _vector(command.get("source_position", []))
	var accepted_tick := float(command.get("accepted_tick", -1.0))
	if trigger_count <= 0 or not source_position.is_finite() \
			or not is_finite(accepted_tick) or accepted_tick < 0.0:
		return {}
	return {
		"family": EXPECTED_FAMILY,
		"subtype": EXPECTED_SUBTYPE,
		"effect": EXPECTED_EFFECT,
		"source_id": expected_terminal_source_id(),
		"source_authority_key": expected_terminal_authority_key(),
		"source_trigger_count": trigger_count,
		"actor": EXPECTED_ACTOR,
		"source_position": _vector_data(source_position),
		"accepted_tick": accepted_tick,
	}


func _live_source_matches(command: Dictionary) -> bool:
	var source_id := expected_terminal_source_id()
	if _game_state == null or _game_state.scheduler == null \
			or not _game_state.characters.has(EXPECTED_ACTOR) \
			or not _game_state.has_interactable(source_id):
		return false
	var source: Dictionary = _game_state.get_interactable(source_id)
	if not _registry_receipt_matches(source, command):
		return false
	var command_position := _vector(command.get("source_position", []))
	var registered_position := _vector(source.get("position", Vector3(INF, INF, INF)))
	if command_position.distance_to(registered_position) > POSITION_EPSILON:
		return false
	var radius := maxf(0.0, float(source.get("radius", 0.0)))
	if _game_state.get_position(EXPECTED_ACTOR).distance_to(registered_position) \
			> radius + POSITION_EPSILON:
		return false
	var now := _scheduler_tick()
	return absf(float(command.get("accepted_tick", -1.0)) - now) <= TICK_EPSILON \
		and _source_authority_matches(command)


func _registry_receipt_matches(source: Dictionary, command: Dictionary) -> bool:
	return bool(source.get("one_shot", false)) \
		and bool(source.get("triggered", false)) \
		and not bool(source.get("enabled", true)) \
		and int(source.get("trigger_count", 0)) \
			== int(command.get("source_trigger_count", -1)) \
		and str(source.get("last_trigger_character", "")) == EXPECTED_ACTOR


func _source_authority_matches(command: Dictionary) -> bool:
	var raw: Variant = _game_state.get_world_state(expected_terminal_authority_key(), {})
	if not raw is Dictionary:
		return false
	var source := raw as Dictionary
	if str(source.get("contract", "")) != TERMINAL_CONTRACT \
			or int(source.get("version", 0)) != TERMINAL_AUTHORITY_VERSION \
			or str(source.get("stable_id", "")) != _source_terminal_stable_id \
			or str(source.get("phase", "")) != "accepted" \
			or str(source.get("family", "")) != EXPECTED_FAMILY \
			or str(source.get("subtype", "")) != EXPECTED_SUBTYPE \
			or str(source.get("effect", "")) != EXPECTED_EFFECT \
			or not source.get("command", null) is Dictionary:
		return false
	var normalized := _normalize_command(source.get("command", {}) as Dictionary)
	return not normalized.is_empty() and normalized == command


func _authority_allows_command() -> bool:
	return _valid_retracted_authority(_saved_authority())


func _reconcile_target(enemy_id: String, emit_signals: bool) -> bool:
	var saved := _saved_authority()
	if not _valid_exposed_authority(saved):
		return false
	var receipt := _target_receipt(saved, enemy_id)
	var status := str(receipt.get("status", ""))
	if status in [TARGET_APPLIED, TARGET_DEAD]:
		return true
	if _enemy_lure_authority_matches(enemy_id, saved):
		_set_target_status(enemy_id, TARGET_APPLIED, _scheduler_tick())
		if emit_signals:
			target_lured.emit(enemy_id, get_state())
		return true
	return _reconcile_bound_target(enemy_id, saved, emit_signals)


func _reconcile_bound_target(
		enemy_id: String,
		saved: Dictionary,
		emit_signals: bool
	) -> bool:
	var value: Variant = _enemies.get(enemy_id)
	if not value is Enemy or not is_instance_valid(value):
		return false
	var enemy := value as Enemy
	if not _enemy_fsm_available(enemy_id, enemy):
		if emit_signals:
			target_lure_pending.emit(enemy_id, "fsm_unavailable")
		return false
	var availability := enemy.get_lure_availability()
	if availability == "dead":
		_set_target_status(enemy_id, TARGET_DEAD, _scheduler_tick())
		return true
	if availability != "available":
		if emit_signals:
			target_lure_pending.emit(enemy_id, availability)
		return false
	return _attempt_available_target(enemy_id, saved, enemy, emit_signals)


func _attempt_available_target(
		enemy_id: String,
		saved: Dictionary,
		enemy: Enemy,
		emit_signals: bool
	) -> bool:
	# The exposed authority and physical presenter must already exist before Enemy is touched.
	if not _fixture_presenter_is_exposed():
		return false
	var activation_serial := int(saved.get("activation_serial", 0))
	if not _begin_target_attempt(enemy_id):
		return false
	var accepted := enemy.lure_to(
		_fixture_exposed_position,
		_lure_duration,
		{
			"source_key": authority_state_key(),
			"activation_serial": activation_serial,
		}
	)
	var latest := _saved_authority()
	if accepted and _enemy_lure_authority_matches(enemy_id, latest):
		_set_target_status(enemy_id, TARGET_APPLIED, _scheduler_tick())
		if emit_signals:
			target_lured.emit(enemy_id, get_state())
		return true
	_set_target_status(enemy_id, TARGET_PENDING, -1.0)
	if emit_signals:
		target_lure_pending.emit(enemy_id, enemy.get_lure_availability())
	return false


func _enemy_fsm_available(enemy_id: String, enemy: Enemy) -> bool:
	if enemy == null or not is_instance_valid(enemy) or enemy.game_state != _game_state \
			or str(enemy.char_id) != enemy_id or enemy.get_state().is_empty() \
			or not _game_state.characters.has(enemy_id):
		return false
	var raw: Variant = _game_state.get_world_state(ENEMY_KEY_PREFIX + enemy_id, {})
	return raw is Dictionary \
		and int((raw as Dictionary).get("version", 0)) > 0 \
		and str((raw as Dictionary).get("char_id", "")) == enemy_id


func _enemy_lure_authority_matches(enemy_id: String, receiver_state: Dictionary) -> bool:
	if not _valid_exposed_authority(receiver_state):
		return false
	var raw: Variant = _game_state.get_world_state(ENEMY_KEY_PREFIX + enemy_id, {})
	if not raw is Dictionary:
		return false
	var enemy_state := raw as Dictionary
	return str(enemy_state.get("char_id", "")) == enemy_id \
		and str(enemy_state.get("state", "")) == "lured" \
		and str(enemy_state.get("lure_source_key", "")) == authority_state_key() \
		and int(enemy_state.get("lure_source_activation_serial", 0)) \
			== int(receiver_state.get("activation_serial", -1)) \
		and _vector(enemy_state.get("lure_settle", [])).distance_to(
			_fixture_exposed_position
		) <= POSITION_EPSILON


func _begin_target_attempt(enemy_id: String) -> bool:
	var saved := _saved_authority().duplicate(true)
	if not _valid_exposed_authority(saved):
		return false
	var receipt := _target_receipt(saved, enemy_id)
	if str(receipt.get("status", "")) not in [TARGET_PENDING, TARGET_APPLYING]:
		return false
	receipt["status"] = TARGET_APPLYING
	receipt["attempt_count"] = int(receipt.get("attempt_count", 0)) + 1
	receipt["last_attempt_tick"] = _scheduler_tick()
	receipt["applied_tick"] = -1.0
	_game_state.set_world_state(authority_state_key(), saved)
	return true


func _set_target_status(enemy_id: String, status: String, applied_tick: float) -> bool:
	if status not in [TARGET_PENDING, TARGET_APPLIED, TARGET_DEAD]:
		return false
	var saved := _saved_authority().duplicate(true)
	if not _valid_exposed_authority(saved):
		return false
	var receipt := _target_receipt(saved, enemy_id)
	if receipt.is_empty():
		return false
	receipt["status"] = status
	receipt["applied_tick"] = applied_tick if status in [TARGET_APPLIED, TARGET_DEAD] else -1.0
	_game_state.set_world_state(authority_state_key(), saved)
	return true


func _repair_interrupted_target_receipts() -> void:
	var saved := _saved_authority().duplicate(true)
	if not _valid_exposed_authority(saved):
		return
	var changed := false
	for receipt_value in saved.get("target_receipts", []) as Array:
		var receipt := receipt_value as Dictionary
		var enemy_id := str(receipt.get("char_id", ""))
		var status := str(receipt.get("status", ""))
		if status == TARGET_APPLYING:
			if _enemy_lure_authority_matches(enemy_id, saved):
				receipt["status"] = TARGET_APPLIED
				receipt["applied_tick"] = maxf(
					0.0,
					float(receipt.get("last_attempt_tick", _scheduler_tick()))
				)
			else:
				receipt["status"] = TARGET_PENDING
				receipt["applied_tick"] = -1.0
			changed = true
		elif status == TARGET_PENDING and _enemy_lure_authority_matches(enemy_id, saved):
			receipt["status"] = TARGET_APPLIED
			receipt["applied_tick"] = maxf(0.0, _scheduler_tick())
			changed = true
	if changed:
		_game_state.set_world_state(authority_state_key(), saved)


func _target_receipt(saved: Dictionary, enemy_id: String) -> Dictionary:
	for value in saved.get("target_receipts", []) as Array:
		if value is Dictionary and str((value as Dictionary).get("char_id", "")) == enemy_id:
			return value as Dictionary
	return {}


func _retracted_authority() -> Dictionary:
	return {
		"contract": STATE_CONTRACT,
		"version": AUTHORITY_VERSION,
		"receiver_id": _receiver_id,
		"phase": PHASE_RETRACTED,
		"source_terminal_stable_id": _source_terminal_stable_id,
		"fixture_retracted_position": _vector_data(_fixture_retracted_position),
		"fixture_exposed_position": _vector_data(_fixture_exposed_position),
		"fixture_size": _vector_data(_fixture_size),
		"lure_duration": _lure_duration,
		"actor": "",
		"accepted_tick": -1.0,
		"activation_serial": 0,
		"next_reconcile_deadline": -1.0,
		"receipt_provenance": {},
		"target_receipts": _target_receipts(TARGET_DORMANT),
	}


func _exposed_authority(receipt: Dictionary) -> Dictionary:
	var provenance := receipt.duplicate(true)
	provenance["source_contract"] = TERMINAL_CONTRACT
	return {
		"contract": STATE_CONTRACT,
		"version": AUTHORITY_VERSION,
		"receiver_id": _receiver_id,
		"phase": PHASE_EXPOSED,
		"source_terminal_stable_id": _source_terminal_stable_id,
		"fixture_retracted_position": _vector_data(_fixture_retracted_position),
		"fixture_exposed_position": _vector_data(_fixture_exposed_position),
		"fixture_size": _vector_data(_fixture_size),
		"lure_duration": _lure_duration,
		"actor": EXPECTED_ACTOR,
		"accepted_tick": float(receipt.get("accepted_tick", _scheduler_tick())),
		"activation_serial": int(receipt.get("source_trigger_count", 0)),
		"next_reconcile_deadline": -1.0,
		"receipt_provenance": provenance,
		"target_receipts": _target_receipts(TARGET_PENDING),
	}


func _target_receipts(initial_status: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for enemy_id in _target_ids:
		result.append({
			"char_id": enemy_id,
			"status": initial_status,
			"attempt_count": 0,
			"last_attempt_tick": -1.0,
			"applied_tick": -1.0,
		})
	return result


func _valid_retracted_authority(saved: Dictionary) -> bool:
	return _valid_common_authority(saved) \
		and str(saved.get("phase", "")) == PHASE_RETRACTED \
		and str(saved.get("actor", "")) == "" \
		and float(saved.get("accepted_tick", -1.0)) < 0.0 \
		and int(saved.get("activation_serial", -1)) == 0 \
		and saved.get("receipt_provenance", null) is Dictionary \
		and (saved.get("receipt_provenance", {}) as Dictionary).is_empty() \
		and _valid_target_receipts(saved.get("target_receipts", []), TARGET_DORMANT)


func _valid_exposed_authority(saved: Dictionary) -> bool:
	if not _valid_common_authority(saved) \
			or str(saved.get("phase", "")) != PHASE_EXPOSED \
			or str(saved.get("actor", "")) != EXPECTED_ACTOR \
			or not is_finite(float(saved.get("accepted_tick", -1.0))) \
			or float(saved.get("accepted_tick", -1.0)) < 0.0 \
			or int(saved.get("activation_serial", 0)) <= 0:
		return false
	var provenance_v: Variant = saved.get("receipt_provenance", null)
	if not provenance_v is Dictionary:
		return false
	var provenance := provenance_v as Dictionary
	var command := _normalize_command(provenance)
	if command.is_empty() \
			or str(provenance.get("source_contract", "")) != TERMINAL_CONTRACT \
			or int(command.get("source_trigger_count", -1)) \
				!= int(saved.get("activation_serial", 0)) \
			or not is_equal_approx(
				float(command.get("accepted_tick", -1.0)),
				float(saved.get("accepted_tick", -2.0))
			):
		return false
	return _valid_target_receipts(saved.get("target_receipts", []), "")


func _valid_common_authority(saved: Dictionary) -> bool:
	return not saved.is_empty() \
		and str(saved.get("contract", "")) == STATE_CONTRACT \
		and int(saved.get("version", 0)) == AUTHORITY_VERSION \
		and str(saved.get("receiver_id", "")) == _receiver_id \
		and str(saved.get("source_terminal_stable_id", "")) \
			== _source_terminal_stable_id \
		and _vector(saved.get("fixture_retracted_position", [])).is_equal_approx(
			_fixture_retracted_position
		) \
		and _vector(saved.get("fixture_exposed_position", [])).is_equal_approx(
			_fixture_exposed_position
		) \
		and _vector(saved.get("fixture_size", [])).is_equal_approx(_fixture_size) \
		and is_equal_approx(float(saved.get("lure_duration", -1.0)), _lure_duration) \
		and is_finite(float(saved.get("next_reconcile_deadline", -1.0))) \
		and float(saved.get("next_reconcile_deadline", -1.0)) >= -1.0


func _valid_target_receipts(value: Variant, required_status: String) -> bool:
	if not value is Array or value.size() != _target_ids.size():
		return false
	var receipts := value as Array
	for index in range(_target_ids.size()):
		if not receipts[index] is Dictionary:
			return false
		var receipt := receipts[index] as Dictionary
		var status := str(receipt.get("status", ""))
		if str(receipt.get("char_id", "")) != _target_ids[index] \
				or status not in TARGET_PHASES \
				or (not required_status.is_empty() and status != required_status) \
				or int(receipt.get("attempt_count", -1)) < 0 \
				or not is_finite(float(receipt.get("last_attempt_tick", -1.0))) \
				or not is_finite(float(receipt.get("applied_tick", -1.0))):
			return false
		if status in [TARGET_DORMANT, TARGET_PENDING] \
				and float(receipt.get("applied_tick", -1.0)) >= 0.0:
			return false
		if status in [TARGET_APPLIED, TARGET_DEAD] \
				and float(receipt.get("applied_tick", -1.0)) < 0.0:
			return false
	return true


func _saved_authority() -> Dictionary:
	if not _configured or _game_state == null:
		return {}
	var raw: Variant = _game_state.get_world_state(authority_state_key(), {})
	return raw as Dictionary if raw is Dictionary else {}


func _normalize_target_ids(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var enemy_id := str(value).strip_edges()
		if enemy_id.is_empty() or result.has(enemy_id):
			return []
		result.append(enemy_id)
	result.sort()
	return result


func _bound_enemy_ids() -> Array[String]:
	var result: Array[String] = []
	for enemy_id in _target_ids:
		var value: Variant = _enemies.get(enemy_id)
		if value is Enemy and is_instance_valid(value):
			result.append(enemy_id)
	return result


func _has_bound_pending_target() -> bool:
	var saved := _saved_authority()
	if not _valid_exposed_authority(saved):
		return false
	for enemy_id in _target_ids:
		var status := str(_target_receipt(saved, enemy_id).get("status", ""))
		var value: Variant = _enemies.get(enemy_id)
		if status in [TARGET_PENDING, TARGET_APPLYING] \
				and value is Enemy and is_instance_valid(value):
			return true
	return false


func _arm_reconcile_retry(delay: float) -> void:
	_cancel_reconcile_retry()
	if not _has_bound_pending_target():
		_set_reconcile_deadline(-1.0)
		return
	_schedule_reconcile_at(_scheduler_tick() + maxf(RESTORE_RETRY_DELAY, delay))


func _arm_restored_reconcile_retry() -> void:
	_cancel_reconcile_retry()
	if not _has_bound_pending_target():
		_set_reconcile_deadline(-1.0)
		return
	var saved := _saved_authority()
	var deadline := float(saved.get("next_reconcile_deadline", -1.0))
	if deadline < _scheduler_tick() + RESTORE_RETRY_DELAY:
		deadline = _scheduler_tick() + RESTORE_RETRY_DELAY
	_schedule_reconcile_at(deadline)


func _schedule_reconcile_at(deadline: float) -> void:
	_set_reconcile_deadline(deadline)
	var generation := _retry_generation
	_game_state.scheduler.schedule_at(
		deadline,
		_on_reconcile_retry.bind(generation),
		_retry_tag()
	)


func _set_reconcile_deadline(deadline: float) -> void:
	var saved := _saved_authority().duplicate(true)
	if not _valid_exposed_authority(saved) \
			or is_equal_approx(
				float(saved.get("next_reconcile_deadline", -1.0)),
				deadline
			):
		return
	saved["next_reconcile_deadline"] = deadline
	_game_state.set_world_state(authority_state_key(), saved)


func _cancel_reconcile_retry() -> void:
	_retry_generation += 1
	if _game_state != null and _game_state.scheduler != null \
			and _game_state.scheduler.has_method("cancel_tag") \
			and not _receiver_id.is_empty():
		_game_state.scheduler.cancel_tag(_retry_tag())


func _on_reconcile_retry(generation: int) -> void:
	if generation != _retry_generation:
		return
	reconcile_targets(true)


func _retry_tag() -> String:
	return "iron_purge_reconcile:%s" % _receiver_id


func _apply_fixture_presenter(phase: String) -> void:
	if not is_instance_valid(_fixture_root):
		return
	var exposed := phase == PHASE_EXPOSED
	_fixture_root.position = (
		_fixture_exposed_position - _fixture_retracted_position
		if exposed
		else Vector3.ZERO
	)
	if is_instance_valid(_fixture_mesh):
		var material := _fixture_mesh.material_override as StandardMaterial3D
		if material != null:
			var tint := Color(0.92, 0.42, 0.12) if exposed else Color(0.37, 0.20, 0.12)
			material.albedo_color = tint.darkened(0.52)
			material.emission = tint
			material.emission_energy_multiplier = 2.1 if exposed else 0.35
	if is_instance_valid(_status_label):
		_status_label.text = (
			"IRON PURGE // FIXTURE EXPOSED"
			if exposed
			else "IRON PURGE // FIXTURE RETRACTED"
		)
		_status_label.modulate = (
			Color(1.0, 0.58, 0.23)
			if exposed
			else Color(0.58, 0.40, 0.30)
		)


func _fixture_presenter_is_exposed() -> bool:
	return is_instance_valid(_fixture_root) \
		and _fixture_root.position.is_equal_approx(
			_fixture_exposed_position - _fixture_retracted_position
		)


func _build_fixture_visual() -> void:
	_housing = MeshInstance3D.new()
	_housing.name = "PurgeHousing"
	var housing_mesh := BoxMesh.new()
	housing_mesh.size = _fixture_size + Vector3(0.65, 0.65, 0.65)
	_housing.mesh = housing_mesh
	_housing.material_override = _material(
		Color(0.055, 0.045, 0.040),
		Color(0.22, 0.10, 0.055),
		0.25
	)
	add_child(_housing)

	_fixture_root = Node3D.new()
	_fixture_root.name = "SacrificialIronFixture"
	_fixture_root.set_meta("iron_source", true)
	_fixture_root.set_meta("iron_source_receiver_id", _receiver_id)
	_fixture_root.set_meta("asset_authoring_status", FIXTURE_VISUAL_STATUS)
	add_child(_fixture_root)

	_fixture_mesh = MeshInstance3D.new()
	_fixture_mesh.name = "IronCore"
	var fixture_box := BoxMesh.new()
	fixture_box.size = _fixture_size
	_fixture_mesh.mesh = fixture_box
	_fixture_mesh.material_override = _material(
		Color(0.14, 0.065, 0.035),
		Color(0.37, 0.20, 0.12),
		0.35
	)
	_fixture_root.add_child(_fixture_mesh)

	var body := StaticBody3D.new()
	body.name = "IronFixtureBody"
	body.collision_layer = 1
	body.collision_mask = 0
	_fixture_collision = CollisionShape3D.new()
	_fixture_collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = _fixture_size
	_fixture_collision.shape = shape
	body.add_child(_fixture_collision)
	_fixture_root.add_child(body)

	for rib_index in range(3):
		var rib := MeshInstance3D.new()
		rib.name = "IronRib_%d" % rib_index
		var rib_mesh := BoxMesh.new()
		rib_mesh.size = Vector3(
			_fixture_size.x + 0.10,
			0.08,
			_fixture_size.z + 0.10
		)
		rib.mesh = rib_mesh
		rib.position.y = lerpf(
			-_fixture_size.y * 0.38,
			_fixture_size.y * 0.38,
			float(rib_index) / 2.0
		)
		rib.material_override = _material(
			Color(0.20, 0.11, 0.06),
			Color(0.48, 0.20, 0.08),
			0.30
		)
		_fixture_root.add_child(rib)

	_status_label = Label3D.new()
	_status_label.name = "PurgeStatus"
	_status_label.position = Vector3(
		0.0,
		_fixture_size.y * 0.5 + 0.75,
		0.0
	)
	_status_label.font_size = 28
	_status_label.pixel_size = 0.006
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.no_depth_test = true
	_status_label.set_meta("camera_occlusion_exempt", true)
	add_child(_status_label)
	_apply_fixture_presenter(PHASE_RETRACTED)


func _material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.88
	material.metallic = 0.72
	material.emission_enabled = energy > 0.0
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material


func _valid_size(value: Vector3) -> bool:
	return value.is_finite() and value.x > 0.0 and value.y > 0.0 and value.z > 0.0


func _vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3(INF, INF, INF)


func _vector_data(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _scheduler_tick() -> float:
	if _game_state != null and _game_state.scheduler != null:
		return float(_game_state.scheduler.get_current_tick())
	return 0.0


func _exit_tree() -> void:
	_cancel_reconcile_retry()
