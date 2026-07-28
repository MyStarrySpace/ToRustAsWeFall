class_name PartyGate3D
extends Node3D

## Reusable two-phase world gate.
##
## `begin_open()` commits a complete scheduler window to GameState.world_state before an authored
## animation starts. `commit_open()` validates the party again at the saved absolute deadline before
## collision/navigation are removed. A presenter reconstructed halfway through therefore resumes the
## same commitment instead of granting a fresh timer or silently returning to CLOSED.

signal opening_started
signal opened
signal blocked(reason: StringName)

enum State { CLOSED, OPENING, OPEN }

const STATE_CONTRACT := "party_gate_3d/v1"
const PHASE_CLOSED := "closed"
const PHASE_OPENING := "opening"
const PHASE_OPEN := "open"

@export var required_members := PackedStringArray()
@export var readiness_radius := 2.0
@export var interaction_anchor_path := NodePath("Markers/InteractionAnchor")
@export var blocker_shape_path := NodePath("RubbleBlocker/BlockerShape")
@export var navigation_padding := Vector2.ZERO
## Stable authored identity. When omitted, setup derives one from the node name, anchor, and level.
@export var authority_id := ""
## The gameplay duration of OPENING. Animation length is presentation and must not own this clock.
@export var opening_duration := 1.15

var state := State.CLOSED
var _game_state: GameState
var _grid: GridWorld
var _level := 0
var _party: Array = []
var _policy := Gate.new()
var _removed_allowed_cells: Array[Vector2i] = []
var _added_dynamic_cells: Array[Vector2i] = []
var _dynamic_blocker_id := ""
var _resolved_authority_id := ""
var _opening_handle := 0
var _configured := false


func setup(game_state: GameState, grid: GridWorld, level: int, party: Array) -> void:
	_cancel_opening_callback()
	_release_navigation_barrier()
	_game_state = game_state
	_grid = grid
	_level = level
	_party = party.duplicate()
	_policy.id = StringName(name)
	_policy.position = get_interaction_anchor()
	_policy.radius = readiness_radius
	_policy.require_proximity = true
	_policy.required_members.clear()
	for member in required_members:
		_policy.required_members.append(StringName(member))
	_resolved_authority_id = _resolve_authority_id()
	_dynamic_blocker_id = "party_gate_%s" % str(absi(authority_state_key().hash()))
	_configured = true
	_ensure_authority_record()
	_restore_authoritative_runtime()


func get_interaction_anchor() -> Vector3:
	var anchor := get_node_or_null(interaction_anchor_path) as Node3D
	return anchor.global_position if anchor != null else global_position


func blocking_reason() -> StringName:
	if _game_state == null:
		return &"missing_game_state"
	_policy.position = get_interaction_anchor()
	_policy.radius = readiness_radius
	return _policy.blocking_reason(_game_state, _party)


func is_satisfied() -> bool:
	return blocking_reason() == &""


func begin_open(context: Dictionary = {}) -> bool:
	_restore_authoritative_runtime(false)
	if state != State.CLOSED:
		return false
	if _game_state == null or _game_state.scheduler == null or opening_duration <= 0.0:
		blocked.emit(&"missing_scheduler")
		return false
	var reason := blocking_reason()
	if reason != &"":
		blocked.emit(reason)
		return false
	var now := float(_game_state.scheduler.get_current_tick())
	_publish_authority({
		"contract": STATE_CONTRACT,
		"authority_id": _resolved_authority_id,
		"phase": PHASE_OPENING,
		"start_tick": now,
		"end_tick": now + opening_duration,
		"required_members": Array(required_members),
		# Mechanism owners may attach portable causal context (for example the
		# route that committed an ordered seal). It lives beside the phase and
		# deadline so a reload cannot restore one without the others.
		"context": context.duplicate(true),
	})
	opening_started.emit()
	return true


## Commit only after the presentation delay completes. A member who becomes
## unavailable or leaves the work radius during that delay keeps the barrier shut.
func commit_open() -> bool:
	var saved := get_authority_state()
	var saved_phase := str(saved.get("phase", PHASE_CLOSED))
	if saved_phase != PHASE_OPENING:
		state = State.OPEN if saved_phase == PHASE_OPEN else State.CLOSED
		return state == State.OPEN
	state = State.OPENING
	var now := float(_game_state.scheduler.get_current_tick()) \
			if _game_state != null and _game_state.scheduler != null else -INF
	# The public API cannot be used to skip the authored commitment window.
	if now + 0.000001 < float(saved.get("end_tick", INF)):
		return false
	var reason := blocking_reason()
	if reason != &"":
		_publish_authority(_closed_record())
		blocked.emit(reason)
		return false
	var saved_context: Dictionary = {}
	var saved_context_v: Variant = saved.get("context", {})
	if saved_context_v is Dictionary:
		saved_context = (saved_context_v as Dictionary).duplicate(true)
	_publish_authority({
		"contract": STATE_CONTRACT,
		"authority_id": _resolved_authority_id,
		"phase": PHASE_OPEN,
		"start_tick": float(saved.get("start_tick", now)),
		"end_tick": float(saved.get("end_tick", now)),
		"required_members": Array(required_members),
		"context": saved_context,
	})
	opened.emit()
	return true


func cancel_open() -> void:
	_restore_authoritative_runtime(false)
	if state == State.OPENING:
		_publish_authority(_closed_record())


## Replace an invalid or absent host commitment with the physical baseline.
## Hosts use this while validating cross-mechanism ordering during attachment;
## ordinary interaction code should prefer cancel_open(), which only cancels an
## active opening and can never close an already-open gate.
func restore_closed_baseline() -> void:
	if not _configured:
		return
	_publish_authority(_closed_record())


## Stable GameState namespace used by saves, rollback, and event replay.
func authority_state_key() -> String:
	var resolved := _resolved_authority_id
	if resolved.is_empty():
		resolved = authority_id.strip_edges()
	if resolved.is_empty():
		resolved = str(name) if not str(name).is_empty() else "unconfigured"
	return "gameplay:party_gate:%s" % resolved


func get_authority_state() -> Dictionary:
	if _game_state == null or not _game_state.has_method("get_world_state"):
		return {}
	var value: Variant = _game_state.get_world_state(authority_state_key(), {})
	if not (value is Dictionary):
		return {}
	var saved := (value as Dictionary).duplicate(true)
	if str(saved.get("contract", "")) != STATE_CONTRACT \
			or str(saved.get("authority_id", "")) != _resolved_authority_id:
		return {}
	return saved


## TutorialSequence calls this after replacing GameState and clearing all opaque scheduler Callables.
## Collision, navigation, animation, and the one remaining deadline are rebuilt from world truth.
func on_game_state_snapshot_restored() -> void:
	_restore_authoritative_runtime()


func _ensure_authority_record() -> void:
	if not get_authority_state().is_empty():
		return
	_publish_authority(_closed_record())


func _closed_record() -> Dictionary:
	return {
		"contract": STATE_CONTRACT,
		"authority_id": _resolved_authority_id,
		"phase": PHASE_CLOSED,
		"start_tick": -1.0,
		"end_tick": -1.0,
		"required_members": Array(required_members),
		"context": {},
	}


func _publish_authority(saved: Dictionary) -> void:
	if _game_state == null or not _game_state.has_method("set_world_state"):
		return
	_game_state.set_world_state(authority_state_key(), saved.duplicate(true))
	_restore_authoritative_runtime()


func _restore_authoritative_runtime(rebuild_navigation := true) -> void:
	if not _configured:
		return
	_cancel_opening_callback()
	var saved := get_authority_state()
	if saved.is_empty():
		_ensure_authority_record()
		saved = get_authority_state()
	var phase := str(saved.get("phase", PHASE_CLOSED))
	match phase:
		PHASE_OPENING:
			state = State.OPENING
		PHASE_OPEN:
			state = State.OPEN
		_:
			state = State.CLOSED

	if rebuild_navigation:
		_apply_physical_truth(state == State.OPEN)
	_apply_animation_truth(saved)

	if state != State.OPENING or _game_state == null or _game_state.scheduler == null:
		return
	var end_tick := float(saved.get("end_tick", -1.0))
	var now := float(_game_state.scheduler.get_current_tick())
	if end_tick <= now + 0.000001:
		commit_open()
		return
	_opening_handle = int(_game_state.scheduler.schedule_at(
		end_tick,
		_on_opening_deadline.bind(end_tick),
		_opening_tag()
	))


func _on_opening_deadline(expected_end_tick: float) -> void:
	_opening_handle = 0
	var saved := get_authority_state()
	if str(saved.get("phase", "")) != PHASE_OPENING \
			or not is_equal_approx(float(saved.get("end_tick", -1.0)), expected_end_tick):
		return
	commit_open()


func _cancel_opening_callback() -> void:
	if _game_state != null and _game_state.scheduler != null:
		_game_state.scheduler.cancel_tag(_opening_tag())
	_opening_handle = 0


func _opening_tag() -> String:
	return "party_gate_open_%s" % str(absi(authority_state_key().hash()))


func _resolve_authority_id() -> String:
	var explicit := authority_id.strip_edges()
	if not explicit.is_empty():
		return explicit
	var node_id := str(name).strip_edges()
	if node_id.is_empty():
		node_id = "party_gate"
	var anchor := get_interaction_anchor()
	return "%s@%.3f,%.3f,%.3f:L%d" % [
		node_id, anchor.x, anchor.y, anchor.z, _level,
	]


func _apply_physical_truth(is_open: bool) -> void:
	_release_navigation_barrier()
	if not is_open:
		_apply_navigation_barrier()
	_set_blocker_disabled(is_open)


func _apply_animation_truth(saved: Dictionary) -> void:
	var animation := get_node_or_null("GateAnimation") as AnimationPlayer
	if animation == null:
		return
	var phase := str(saved.get("phase", PHASE_CLOSED))
	if phase == PHASE_CLOSED:
		if animation.has_animation("RESET"):
			animation.play("RESET")
		return
	if not animation.has_animation("clear_together"):
		return
	var length := animation.get_animation("clear_together").length
	var sample := length
	if phase == PHASE_OPENING and _game_state != null and _game_state.scheduler != null:
		sample = clampf(
			float(_game_state.scheduler.get_current_tick()) - float(saved.get("start_tick", 0.0)),
			0.0,
			length
		)
	animation.play("clear_together")
	animation.seek(sample, true)
	if phase == PHASE_OPEN:
		animation.pause()


func navigation_cells() -> Array[Vector2i]:
	if _grid == null:
		return []
	var shape_node := get_node_or_null(blocker_shape_path) as CollisionShape3D
	if shape_node == null or not (shape_node.shape is BoxShape3D):
		return []
	var box := shape_node.shape as BoxShape3D
	var scale := shape_node.global_transform.basis.get_scale().abs()
	var half := box.size * scale * 0.5
	half.x += navigation_padding.x
	half.z += navigation_padding.y
	var center := shape_node.global_position
	var min_cell := _grid.world_to_grid(Vector3(center.x - half.x, center.y, center.z - half.z))
	var max_cell := _grid.world_to_grid(Vector3(center.x + half.x, center.y, center.z + half.z))
	var cells: Array[Vector2i] = []
	for z in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
		for x in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
			cells.append(Vector2i(x, z))
	return cells


func _apply_navigation_barrier() -> void:
	if _grid == null:
		return
	for cell in navigation_cells():
		if _grid.is_level_restricted(_level):
			if _grid.level_allowed[_level].has(cell):
				_removed_allowed_cells.append(cell)
				_grid.disallow_cell_on_level(cell, _level)
		elif not _grid.dynamic_blockers.has(cell):
			_added_dynamic_cells.append(cell)
			_grid.add_dynamic_blocker(cell, _dynamic_blocker_id)


func _release_navigation_barrier() -> void:
	if _grid == null:
		_removed_allowed_cells.clear()
		_added_dynamic_cells.clear()
		return
	for cell in _removed_allowed_cells:
		_grid.allow_cell_on_level(cell, _level)
	_removed_allowed_cells.clear()
	for cell in _added_dynamic_cells:
		if str(_grid.dynamic_blockers.get(cell, "")) == _dynamic_blocker_id:
			_grid.remove_dynamic_blocker(cell)
	_added_dynamic_cells.clear()


func _set_blocker_disabled(disabled: bool) -> void:
	var blocker := get_node_or_null(blocker_shape_path) as CollisionShape3D
	if blocker != null:
		blocker.set_deferred("disabled", disabled)


func _exit_tree() -> void:
	_cancel_opening_callback()
	_release_navigation_barrier()
