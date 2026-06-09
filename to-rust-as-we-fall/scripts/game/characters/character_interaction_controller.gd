class_name CharacterInteractionController
extends Node

## Reusable click-to-interaction coordinator.
## Targets emit interaction_requested; this moves the character toward them.

@export var default_arrival_radius := 0.35
@export var max_grid_search_radius := 4

var character: Node3D
var active_target: Node
var active_target_position := Vector3.ZERO
var _interactor_id := ""   # who is actually servicing active_target (may be a party member, not `character`)
var _bound_roots: Array[Node] = []

signal target_reached(target: Node)
signal target_cancelled(target: Node)

func setup(character_node: Node3D) -> void:
	character = character_node
	if character != null and character.has_signal("arrived") and not character.is_connected("arrived", _on_character_arrived):
		character.connect("arrived", _on_character_arrived)

func _process(_delta: float) -> void:
	_poll_arrival()

func sync_scheduler_visuals() -> void:
	_poll_arrival()

func bind_interaction_root(root: Node) -> void:
	if root == null:
		return
	if not _bound_roots.has(root):
		_bound_roots.append(root)
		if root.has_signal("child_entered_tree") and not root.is_connected("child_entered_tree", _on_bound_child_entered_tree):
			root.connect("child_entered_tree", _on_bound_child_entered_tree)
	bind_interaction_target(root)
	for child in root.get_children():
		bind_interaction_root(child)

func bind_interaction_target(target: Node) -> void:
	if target == null or not target.has_signal("interaction_requested"):
		return
	if not target.is_connected("interaction_requested", _on_interaction_requested):
		target.connect("interaction_requested", _on_interaction_requested)

func _on_bound_child_entered_tree(child: Node) -> void:
	bind_interaction_root(child)

func cancel_active_target() -> void:
	if active_target != null and is_instance_valid(active_target):
		if not _target_feedback_is_managed(active_target) and active_target.has_method("cancel_queued_feedback"):
			active_target.call("cancel_queued_feedback")
		target_cancelled.emit(active_target)
	active_target = null
	_interactor_id = ""

func _on_interaction_requested(target: Node, requested_position: Vector3 = Vector3.INF) -> void:
	if character == null or target == null:
		return
	if not _character_can_accept_interaction():
		return
	cancel_active_target()
	active_target = target
	active_target_position = _resolve_target_position(target, requested_position)
	# Pick WHO services this interaction: a required character if the object names one, else the nearest
	# party member (preferring a free hand for a pickup). May be a party member other than the leader.
	_interactor_id = _pick_interactor_for(target, active_target_position)
	_set_target_active_character(target, _interactor_id)
	if not _target_feedback_is_managed(target) and target.has_method("begin_queued_feedback"):
		target.call("begin_queued_feedback", active_target_position)
	if not _drive_interactor_to(active_target_position):
		_complete_active_target()

## Resolve the servicing character. Single-character scenes (empty party) → the bound character, so
## nothing changes. Multi-character → game_state.pick_interactor over the party.
func _pick_interactor_for(target: Node, target_pos: Vector3) -> String:
	var self_id := _self_id()
	var gs = _character_game_state()
	if gs == null or not gs.has_method("pick_interactor"):
		return self_id
	var candidates: Array = gs.get_party() if gs.has_method("get_party") else []
	if candidates.is_empty():
		candidates = [self_id]
	var picked := str(gs.pick_interactor(
		_target_required_character(target), target_pos, candidates, _target_needs_free_hand(target)))
	return picked if picked != "" else self_id

## Walk the servicing character to the object. The bound character uses its own controller path; any
## other party member is driven by char_id through the data layer (so the move is logged + replay-safe).
func _drive_interactor_to(world_position: Vector3) -> bool:
	var gs = _character_game_state()
	if _interactor_id == "" or _interactor_id == _self_id() or gs == null:
		return _move_character_to(world_position)
	return bool(gs.command_move_to_pos(_interactor_id, world_position))

func _self_id() -> String:
	return str(character.get("char_id")) if character != null else ""

func _character_game_state():
	return character.get("game_state") if character != null else null

func _target_required_character(target: Node) -> String:
	if target == null:
		return ""
	if "required_character" in target:
		return str(target.required_character)
	if target.has_method("get_interaction_delegate"):
		var d = target.call("get_interaction_delegate")
		if d != null and "required_character" in d:
			return str(d.required_character)
	return ""

func _target_needs_free_hand(target: Node) -> bool:
	var probe := target
	if target != null and not target.has_method("requires_free_hand") and target.has_method("get_interaction_delegate"):
		probe = target.call("get_interaction_delegate")
	return probe != null and probe.has_method("requires_free_hand") and bool(probe.call("requires_free_hand"))

func _set_target_active_character(target: Node, id: String) -> void:
	if target == null or id == "":
		return
	if "active_character" in target:
		target.active_character = id
	if target.has_method("get_interaction_delegate"):
		var d = target.call("get_interaction_delegate")
		if d != null and "active_character" in d:
			d.active_character = id

func _resolve_target_position(target: Node, requested_position: Vector3) -> Vector3:
	if target.has_method("get_interaction_target_position"):
		var value = target.call("get_interaction_target_position", _character_position(), requested_position)
		if value is Vector3:
			return value
	if requested_position != Vector3.INF:
		return requested_position
	if target is Node3D:
		var target_node := target as Node3D
		return target_node.global_position
	return _character_position()

func _move_character_to(world_position: Vector3) -> bool:
	if character == null:
		return false
	if character.has_method("move_to_world_position"):
		return bool(character.call("move_to_world_position", world_position))
	if character.has_method("walk_to"):
		character.call("walk_to", world_position)
		return true
	return false

func _on_character_arrived() -> void:
	# The bound character's own arrival — ignore when a DIFFERENT party member is servicing the target
	# (that one's arrival is detected in _poll_arrival via game_state.is_moving).
	if active_target == null or (_interactor_id != "" and _interactor_id != _self_id()):
		return
	_complete_active_target()

func _poll_arrival() -> void:
	if active_target == null or character == null:
		return
	if _interactor_id != "" and _interactor_id != _self_id():
		var gs = _character_game_state()
		if gs != null and gs.has_method("is_moving") and bool(gs.is_moving(_interactor_id)):
			return
		_complete_active_target()
		return
	if character.has_method("is_moving") and bool(character.call("is_moving")):
		return
	_complete_active_target()

func _complete_active_target() -> void:
	if active_target == null:
		return
	var completed := active_target
	if is_instance_valid(completed) and not _target_feedback_is_managed(completed) and completed.has_method("complete_queued_feedback"):
		completed.call("complete_queued_feedback")
	target_reached.emit(completed)
	if is_instance_valid(completed) and completed.has_method("on_interaction_arrived"):
		completed.call("on_interaction_arrived")
	active_target = null
	_interactor_id = ""

func _target_feedback_is_managed(target: Node) -> bool:
	return target != null and target.has_method("is_feedback_managed") and bool(target.call("is_feedback_managed"))

func _character_can_accept_interaction() -> bool:
	if character == null:
		return false
	if character.has_method("is_move_enabled"):
		return bool(character.call("is_move_enabled"))
	var enabled = character.get("_move_enabled")
	return true if enabled == null else bool(enabled)

func _character_position() -> Vector3:
	if character == null:
		return Vector3.ZERO
	var game_state = character.get("game_state")
	var char_id := str(character.get("char_id"))
	if game_state != null and char_id != "" and game_state.characters.has(char_id):
		return game_state.get_position(char_id)
	return character.global_position
