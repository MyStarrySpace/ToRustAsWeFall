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
var _arrival_game_state: Object
# The committed walk's data-space destination + how close counts as ARRIVED
# (the target's interaction radius, padded). A superseding carry (wash sweep,
# knockback, ride) stops the walk WITHOUT arriving — see _complete_active_target.
var _flat_target := Vector3.INF
var _arrival_reach := 1.0
var _redrive_count := 0
const _MAX_REDRIVES := 3

signal target_reached(target: Node)
signal target_cancelled(target: Node)

func setup(character_node: Node3D) -> void:
	character = character_node
	if character != null and character.has_signal("arrived") and not character.is_connected("arrived", _on_character_arrived):
		character.connect("arrived", _on_character_arrived)
	_bind_game_state_arrival()


## Interaction completion is a gameplay receipt, so consume the authoritative GameState
## arrival signal directly. `_poll_arrival()` remains a visual/legacy fallback, but headless
## replay and coarse scheduler steps no longer need a render frame to begin a timed dwell.
func _bind_game_state_arrival() -> void:
	var next_game_state = _character_game_state()
	if _arrival_game_state == next_game_state:
		return
	if is_instance_valid(_arrival_game_state) \
			and _arrival_game_state.has_signal("character_arrived") \
			and _arrival_game_state.is_connected(
				"character_arrived", _on_game_state_character_arrived):
		_arrival_game_state.disconnect(
			"character_arrived", _on_game_state_character_arrived)
	_arrival_game_state = next_game_state
	if is_instance_valid(_arrival_game_state) \
			and _arrival_game_state.has_signal("character_arrived") \
			and not _arrival_game_state.is_connected(
				"character_arrived", _on_game_state_character_arrived):
		_arrival_game_state.connect(
			"character_arrived", _on_game_state_character_arrived)


func _on_game_state_character_arrived(id: String) -> void:
	if active_target == null or _interactor_id == "" or id != _interactor_id:
		return
	_complete_active_target()

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
	_bind_game_state_arrival()
	if not _character_can_accept_interaction():
		return
	cancel_active_target()
	active_target = target
	active_target_position = _resolve_target_position(target, requested_position)
	# On a WARPED scene (the channels helix) command_move_to_pos and pick_interactor are FLAT data-layer APIs,
	# but the resolved target is in WORLD space. Translate ONCE to flat data space for the nearest-member pick and
	# the non-self servicer's move. The SELF path keeps the WORLD position (player._set_click_target re-applies
	# coord_map.to_data, so handing it flat would double-warp), as does the glow origin. Flat scenes (no coord_map)
	# are byte-identical: flat == world. Without this a non-self party member walked to a wrong cell on the helix
	# and never reached the object, so the queued glow never tracked the real walk-to-arrival.
	var gs = _character_game_state()
	var flat_target := active_target_position
	# A warped interactable retains the exact authored data position used to build
	# it. Prefer that source over a world->data round trip: a helix map can recover
	# route progress and lane from the rendered point, but it cannot infer which
	# stacked gameplay floor originally contributed the point's height.
	if target.has_meta("flat_authored_position"):
		var authored_target: Variant = target.get_meta("flat_authored_position")
		if authored_target is Vector3:
			flat_target = authored_target as Vector3
	elif gs != null and gs.coord_map != null:
		flat_target = gs.coord_map.to_data(active_target_position)
	# Pick WHO services this interaction: a required character if the object names one, else the nearest
	# party member (preferring a free hand for a pickup). May be a party member other than the leader.
	_interactor_id = _pick_interactor_for(target, flat_target)
	_flat_target = flat_target
	_redrive_count = 0
	_arrival_reach = 1.0
	var reach_probe := target
	if target != null and not ("interaction_radius" in target) and target.has_method("get_interaction_delegate"):
		reach_probe = target.call("get_interaction_delegate")
	if reach_probe != null and "interaction_radius" in reach_probe:
		_arrival_reach = maxf(1.0, float(reach_probe.interaction_radius) + 0.5)
	_set_target_active_character(target, _interactor_id)
	if not _target_feedback_is_managed(target) and target.has_method("begin_queued_feedback"):
		target.call("begin_queued_feedback", active_target_position, _interactor_color())
	if not _drive_interactor_to(active_target_position, flat_target):
		_complete_active_target()

## The queued-feedback tint: the SERVICING character's color (same ownership language as the
## hover grid / path ribbon), falling back to the host's color, then the legacy orange.
func _interactor_color() -> Color:
	if character != null and "color" in character:
		if not ("char_id" in character) or String(character.char_id) == _interactor_id or _interactor_id == "":
			return character.color
		if character.has_method("_find_char_node"):
			var node = character.call("_find_char_node", _interactor_id)
			if node != null and "color" in node:
				return node.color
		return character.color
	return Color(1.0, 0.62, 0.12)

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

## Walk the servicing character to the object. The bound character uses its own controller path with the WORLD
## position (it re-translates warped scenes itself); any OTHER party member is driven by char_id through the FLAT
## data layer (command_move_to_pos), so it's logged + replay-safe and lands on the right cell on the helix.
func _drive_interactor_to(world_position: Vector3, flat_position: Vector3) -> bool:
	var gs = _character_game_state()
	if _interactor_id == "" or gs == null:
		return _move_character_to(world_position)
	# In warped space, drive even the bound/self character through the data-layer
	# target. Feeding the rendered point back through Player would lose the authored
	# stacked-floor identity. GameState still owns pathfinding, floor links, arrival
	# receipts, logging, and replay for this ordinary interaction walk.
	if _interactor_id != _self_id() or gs.coord_map != null:
		return bool(gs.command_move_to_pos(_interactor_id, flat_position))
	return _move_character_to(world_position)

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
	if active_target == null or not is_instance_valid(active_target):
		active_target = null
		_interactor_id = ""
		return
	# THE CLICK KEEPS ITS PROMISE: "stopped moving" is not "arrived". A wash
	# sweep / knockback / ride SUPERSEDES the committed walk and dumps the
	# servicer elsewhere — mid-carry we wait, and a landing outside the
	# target's reach RE-DRIVES the same commitment (bounded) instead of
	# completing at the wrong spot, where a strict validator truthfully
	# refuses and the player's click dies silently (the wash_ascent flure
	# contract catch).
	var gs_arr = _character_game_state()
	if _interactor_id != "" and gs_arr != null and gs_arr.characters.has(_interactor_id) 			and _flat_target != Vector3.INF:
		if gs_arr.has_method("is_external_traversal_active") 				and bool(gs_arr.is_external_traversal_active(_interactor_id)):
			return
		var at: Vector3 = gs_arr.get_position(_interactor_id)
		if Vector2(at.x, at.z).distance_to(Vector2(_flat_target.x, _flat_target.z)) 				> _arrival_reach and _redrive_count < _MAX_REDRIVES:
			_redrive_count += 1
			gs_arr.command_move_to_pos(_interactor_id, _flat_target)
			return
	var completed := active_target
	# Selection can change while a character is walking. Reassert the servicing body at arrival so
	# a global portrait update cannot make a required-character action complete as somebody else.
	_set_target_active_character(completed, _interactor_id)
	if not _target_feedback_is_managed(completed) and completed.has_method("complete_queued_feedback"):
		completed.call("complete_queued_feedback")
	target_reached.emit(completed)
	if completed.has_method("on_interaction_arrived"):
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
