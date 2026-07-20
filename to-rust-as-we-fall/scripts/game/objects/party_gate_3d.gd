class_name PartyGate3D
extends Node3D

## Reusable two-phase world gate.
##
## `begin_open()` validates the party before an authored animation starts.
## `commit_open()` validates it again before collision/navigation are removed.
## This closes the time-of-check/time-of-use gap common to doors, shared-load
## barriers, elevators, portals, and other delayed transitions.

signal opening_started
signal opened
signal blocked(reason: StringName)

enum State { CLOSED, OPENING, OPEN }

@export var required_members := PackedStringArray()
@export var readiness_radius := 2.0
@export var interaction_anchor_path := NodePath("Markers/InteractionAnchor")
@export var blocker_shape_path := NodePath("RubbleBlocker/BlockerShape")
@export var navigation_padding := Vector2.ZERO

var state := State.CLOSED
var _game_state: GameState
var _grid: GridWorld
var _level := 0
var _party: Array = []
var _policy := Gate.new()
var _removed_allowed_cells: Array[Vector2i] = []
var _added_dynamic_cells: Array[Vector2i] = []
var _dynamic_blocker_id := ""


func setup(game_state: GameState, grid: GridWorld, level: int, party: Array) -> void:
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
	_dynamic_blocker_id = "party_gate_%d" % get_instance_id()
	_apply_navigation_barrier()
	_set_blocker_disabled(false)
	state = State.CLOSED


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


func begin_open() -> bool:
	if state != State.CLOSED:
		return false
	var reason := blocking_reason()
	if reason != &"":
		blocked.emit(reason)
		return false
	state = State.OPENING
	opening_started.emit()
	return true


## Commit only after the presentation delay completes. A member who becomes
## unavailable or leaves the work radius during that delay keeps the barrier shut.
func commit_open() -> bool:
	if state != State.OPENING:
		return state == State.OPEN
	var reason := blocking_reason()
	if reason != &"":
		state = State.CLOSED
		blocked.emit(reason)
		return false
	state = State.OPEN
	_set_blocker_disabled(true)
	_release_navigation_barrier()
	opened.emit()
	return true


func cancel_open() -> void:
	if state == State.OPENING:
		state = State.CLOSED


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
				_grid.level_allowed[_level].erase(cell)
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
	_release_navigation_barrier()
