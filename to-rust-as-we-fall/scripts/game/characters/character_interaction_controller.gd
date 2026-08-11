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
var _request_owner_id := "" # selected body that submitted the current human command
var _bound_roots: Array[Node] = []
var _arrival_game_state: Object
# The committed walk's data-space destination + how close counts as ARRIVED
# (the target's interaction radius, padded). A superseding carry (wash sweep,
# knockback, ride) stops the walk WITHOUT arriving — see _complete_active_target.
var _flat_target := Vector3.INF
## Stable graph destination resolved from the authored interaction approach. Grid
## interactions retain `(cell, level)` all the way through the walk and arrival
## check; an XZ match on another deck is never accepted as reaching the object.
var _navigation_target: Dictionary = {}
## The target's full accepted graph region. A party Rally can legitimately park
## somebody else on the canonical vertex; arrival is therefore membership in
## this annotated region, not equality with one approximate snapped point.
var _navigation_region_contract: Dictionary = {}
var _arrival_reach := 1.0
var _redrive_count := 0
var _target_generation := 0
var _pending_arrival_poll_generation := -1
const _MAX_REDRIVES := 3
const _CONTROLLER_GROUP := &"character_interaction_controllers"

signal target_reached(target: Node)
signal target_cancelled(target: Node)


func _ready() -> void:
	add_to_group(_CONTROLLER_GROUP)

func setup(character_node: Node3D) -> void:
	if character != character_node and is_instance_valid(character) \
			and character.has_signal("arrived") \
			and character.is_connected("arrived", _on_character_arrived):
		character.disconnect("arrived", _on_character_arrived)
	character = character_node
	if character != null and character.has_signal("arrived") and not character.is_connected("arrived", _on_character_arrived):
		character.connect("arrived", _on_character_arrived)
	_bind_game_state_arrival()


## GameState arrival is a movement-PHASE receipt: typed ladder/ramp routes emit it between legs.
## Observe it only to schedule a deferred poll, after the graph executor has advanced the retained
## plan. `sync_scheduler_visuals()` supplies the same post-stack poll for coarse/headless stepping.
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
	# A body that goes down on its way to something is not going to arrive, and the order it was
	# carrying dies with it. Without this the object it was sent to keeps wearing the queued glow
	# for the rest of the run: a standing promise about a character who cannot keep it.
	if is_instance_valid(_arrival_game_state) 			and _arrival_game_state.has_signal("character_downed") 			and not _arrival_game_state.is_connected(
				"character_downed", _on_game_state_character_downed):
		_arrival_game_state.connect(
			"character_downed", _on_game_state_character_downed)


## The one place an approach is abandoned because its actor cannot make it. Routed through
## the same cancel every other abandonment uses, so the queued feedback, the target and the request
## owner all come down together rather than one of them being forgotten.
func _on_game_state_character_downed(id: String) -> void:
	if active_target == null:
		return
	if id != _interactor_id and id != _request_owner_id:
		return
	cancel_active_target()


func _on_game_state_character_arrived(id: String) -> void:
	if active_target == null or _interactor_id == "" or id != _interactor_id:
		return
	_queue_arrival_poll()

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
	_target_generation += 1
	if active_target != null and is_instance_valid(active_target):
		if not _target_feedback_is_managed(active_target) and active_target.has_method("cancel_queued_feedback"):
			active_target.call("cancel_queued_feedback")
		target_cancelled.emit(active_target)
	active_target = null
	_interactor_id = ""
	_request_owner_id = ""
	_navigation_target.clear()
	_navigation_region_contract.clear()

func _on_interaction_requested(target: Node, requested_position: Vector3 = Vector3.INF) -> void:
	if character == null or target == null:
		return
	_bind_game_state_arrival()
	# Every party body owns one coordinator and therefore hears the same target
	# signal. The target latches the selected command owner for this synchronous
	# delivery; the servicing actor may be a different required party member.
	if not _controller_owns_request(target):
		return
	var request_owner := _target_interaction_request_owner(target)
	if request_owner == "":
		request_owner = _self_id()
	cancel_active_target()
	_request_owner_id = request_owner
	active_target = target
	active_target_position = _resolve_target_position(target, requested_position)
	# On a WARPED scene (the channels helix) command_move_to_pos and pick_interactor are FLAT data-layer APIs,
	# but the resolved target is in WORLD space. Translate ONCE to flat data space for the nearest-member pick and
	# the non-self servicer's move. The SELF path keeps the WORLD position (player._set_click_target re-applies
	# coord_map.to_data, so handing it flat would double-warp), as does the glow origin. Flat scenes (no coord_map)
	# are byte-identical: flat == world. Without this a non-self party member walks to a wrong cell on the helix
	# and never reaches the object, so the queued glow never tracks the real walk-to-arrival.
	var gs = _character_game_state()
	var flat_target := _resolve_flat_target_position(target, active_target_position)
	# A warped interactable retains the exact authored data position used to build
	# it. Prefer that source over a world->data round trip: a helix map can recover
	# route progress and lane from the rendered point, but it cannot infer which
	# stacked gameplay floor originally contributed the point's height.
	# Pick WHO services this interaction: a required character if the object names one, else the nearest
	# party member (preferring a free hand for a pickup). May be a party member other than the leader.
	_interactor_id = _pick_interactor_for(target, flat_target)
	_flat_target = flat_target
	if _interactor_id == "" or not _interactor_can_accept_interaction(_interactor_id):
		_refuse_active_target(
			"No available party member can act on that interaction right now.")
		return
	# Ask the clicked object's read-only semantic gate before resolving or
	# committing a route. A rejected click keeps portrait/group selection intact,
	# moves nobody, and presents both the exact red target pulse and the visible
	# prerequisite supplied by the level controller.
	var route_preflight := _target_interaction_route_preflight(
		target, _interactor_id)
	if not bool(route_preflight.get("accepted", true)):
		_refuse_active_target(
			str(route_preflight.get(
				"message", "That interaction is not ready yet.")),
			route_preflight
		)
		return
	_navigation_region_contract = _target_navigation_region(target)
	_navigation_target = _resolve_navigation_target(
		gs,
		_interactor_id,
		flat_target,
		_navigation_region_contract
	)
	if not _navigation_target.is_empty():
		var resolved_data_v: Variant = _navigation_target.get("data_position", null)
		if resolved_data_v is Vector3:
			_flat_target = resolved_data_v as Vector3
	if not _navigation_region_contract.is_empty() and _navigation_target.is_empty():
		var unreachable_route := {
			"accepted": false,
			"code": "interaction_region_unreachable",
			"message": "No connected approach is currently available for that object.",
			"cue": "RESOLVE FIRST // FIND A CONNECTED APPROACH",
		}
		_refuse_active_target(
			str(unreachable_route["message"]), unreachable_route)
		return
	_redrive_count = 0
	_arrival_reach = 1.0
	var reach_probe := target
	if target != null and not ("interaction_radius" in target) and target.has_method("get_interaction_delegate"):
		reach_probe = target.call("get_interaction_delegate")
	if reach_probe != null and "interaction_radius" in reach_probe:
		_arrival_reach = maxf(1.0, float(reach_probe.interaction_radius) + 0.5)
	_cancel_peer_commands_for_interactor(_interactor_id)
	if not _target_feedback_is_managed(target) and target.has_method("begin_queued_feedback"):
		target.call("begin_queued_feedback", active_target_position, _interactor_color())
	if not _drive_interactor_to(active_target_position, flat_target):
		# Even an actor that already occupies the exact interaction vertex must
		# cross the ordinary queued -> arrival -> result presentation order.  A
		# synchronous completion returns to OutlineSurfaceTarget only after it has
		# minted the green/red result; that same click then emits outline_selected,
		# and begin_queued_feedback() erases the result it arrived too late to
		# precede.  Poll on the normal deferred arrival seam instead.  This neither
		# moves nor changes gameplay authority: it only lets the remainder of the
		# physical click finish before the already-reached target resolves.
		_queue_arrival_poll()

## The queued-feedback tint: the SERVICING character's color (same ownership language as the
## hover grid / path ribbon), falling back to the host's color, then a default orange.
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
	var required_id := _target_required_character(target)
	if required_id != "":
		# A semantic actor requirement is exact. Never substitute the nearest
		# available body when that member is absent, downed, or traversing.
		return required_id if candidates.has(required_id) else ""
	# For an unrestricted interaction, choose among bodies that can accept the
	# ordinary routed move now. A named required character must remain the named
	# candidate so the controller can visibly refuse its temporary unavailability
	# instead of substituting a semantically invalid party member.
	if gs.has_method("can_accept_move_command"):
		var available: Array = []
		for candidate_v in candidates:
			var candidate_id := str(candidate_v)
			if bool(gs.call("can_accept_move_command", candidate_id)):
				available.append(candidate_id)
		candidates = available
	var picked := str(gs.pick_interactor(
		"", target_pos, candidates, _target_needs_free_hand(target)))
	return picked

## Walk the one visibly assigned servicing character to the object. Always drive that explicit id through
## GameState when it exists: Player.move_to_world_position is group-aware, so using it for the bound leader
## while several portraits are selected silently converts an interaction walk into party_move_to_cell and
## replans the whole group. The selection must remain intact for group consoles and shelters.
func _drive_interactor_to(world_position: Vector3, flat_position: Vector3) -> bool:
	var gs = _character_game_state()
	if _interactor_id == "" or gs == null:
		return _move_character_to(world_position)
	# This is the normal interaction command path, not a test shortcut: the click chooses
	# the target, the target's required-character contract chooses the actor, and the
	# resulting route/queued glow remain visible and event-logged.
	if not _navigation_target.is_empty() \
			and gs.has_method("command_move_to_navigation_location"):
		return bool(gs.command_move_to_navigation_location(
			_interactor_id, _navigation_target))
	if not _navigation_region_contract.is_empty():
		# A typed region that currently has no free reachable vertex is an honest
		# refusal. Falling through to an approximate world-position command would
		# discard the very graph/level contract the source published.
		return false
	return bool(gs.command_move_to_pos(_interactor_id, flat_position))


## OutlineSurfaceTarget is the rendered click owner, but its delegate owns the
## actual walk-to-use point. On warped/stacked boards both nodes retain their
## original flat position; prefer the delegate so a large outline around a
## shelter cannot reroute the servicing character to the blocked prop centre.
func _resolve_flat_target_position(target: Node, world_position: Vector3) -> Vector3:
	var authored_owner := target
	if target != null and target.has_method("get_interaction_delegate"):
		var delegate_v: Variant = target.call("get_interaction_delegate")
		if delegate_v is Node and is_instance_valid(delegate_v):
			authored_owner = delegate_v as Node
	if authored_owner != null and authored_owner.has_meta("flat_authored_position"):
		var delegated_authored_v: Variant = authored_owner.get_meta(
			"flat_authored_position")
		if delegated_authored_v is Vector3:
			return delegated_authored_v as Vector3
	if target != null and target.has_meta("flat_authored_position"):
		var target_authored_v: Variant = target.get_meta("flat_authored_position")
		if target_authored_v is Vector3:
			return target_authored_v as Vector3
	var gs = _character_game_state()
	if gs != null and "coord_map" in gs and gs.coord_map != null:
		return gs.coord_map.to_data(world_position)
	return world_position


func _resolve_navigation_target(
		gs: Object,
		interactor_id: String,
		flat_position: Vector3,
		interaction_region: Dictionary = {}
	) -> Dictionary:
	if gs == null or interactor_id == "" \
			or not gs.has_method("resolve_navigation_location"):
		return {}
	if not interaction_region.is_empty():
		return resolve_reachable_interaction_location(
			gs, interactor_id, interaction_region
		)
	var resolved_v: Variant = gs.call(
		"resolve_navigation_location", interactor_id, flat_position)
	return (resolved_v as Dictionary).duplicate(true) \
		if resolved_v is Dictionary else {}


## Pure/read-only selection of the concrete arrival vertex for an interaction.
## Prefer the servicing actor's current accepted vertex (the common post-Rally
## case), otherwise choose the shortest reachable vertex not occupied by another
## character.  The returned `(cell, level)` is committed through GameState's
## ordinary movement command; this helper never moves or mutates anybody.
static func resolve_reachable_interaction_location(
		gs: Object, interactor_id: String, interaction_region: Dictionary
	) -> Dictionary:
	if gs == null or interactor_id == "" or interaction_region.is_empty() \
			or not gs.has_method("get_position") \
			or not gs.has_method("get_character_level"):
		return {}
	var grid_v: Variant = gs.get("grid")
	if grid_v == null or not grid_v.has_method("find_multi_level_plan"):
		return {}
	var grid = grid_v
	var actor_position_v: Variant = gs.call("get_position", interactor_id)
	if not (actor_position_v is Vector3):
		return {}
	var actor_position := actor_position_v as Vector3
	var actor_level := int(gs.call("get_character_level", interactor_id))
	var actor_cell: Vector2i = grid.nearest_walkable_cell(
		grid.world_to_grid(actor_position), actor_level
	)
	var candidates: Array[Dictionary] = []
	for vertex_v in interaction_region.get("region_vertices", []):
		var vertex := _navigation_region_vertex(vertex_v)
		if vertex.is_empty():
			continue
		var cell: Vector2i = vertex.get("cell", Vector2i.ZERO)
		var level := int(vertex.get("level", -1))
		if level < 0 or level >= int(grid.level_count) \
				or not grid.is_walkable(cell.x, cell.y, {}, {}, level):
			continue
		candidates.append(vertex)
	if candidates.is_empty():
		return {}
	# Standing inside the accepted region is already a physical arrival. This is
	# deliberately checked before other-body occupancy: overlapping setup bugs do
	# not justify walking the servicing body away and back again.
	for candidate in candidates:
		if int(candidate.get("level", -1)) == actor_level \
				and candidate.get("cell", Vector2i(-1, -1)) == actor_cell:
			return _navigation_location_from_vertex(grid, candidate)

	var occupied_by_other := {}
	var characters_v: Variant = gs.get("characters")
	if characters_v is Dictionary:
		for other_id_v in (characters_v as Dictionary).keys():
			var other_id := str(other_id_v)
			if other_id == interactor_id:
				continue
			var other_position_v: Variant = gs.call("get_position", other_id)
			if not (other_position_v is Vector3):
				continue
			var other_level := int(gs.call("get_character_level", other_id))
			var other_cell: Vector2i = grid.world_to_grid(other_position_v as Vector3)
			occupied_by_other[_navigation_vertex_key(other_cell, other_level)] = true

	# Some graph-edge interactables have one canonical endpoint plus a wider
	# accepted parking region. Route to that endpoint when possible; the region
	# remains authoritative for a body already parked elsewhere by Rally or an
	# annotated traversal consequence.
	if str(interaction_region.get("arrival_policy", "")) == "primary_then_nearest":
		var preferred := _navigation_region_vertex(
			interaction_region.get("approach_vertex", {}))
		if not preferred.is_empty():
			var preferred_cell: Vector2i = preferred.get("cell", Vector2i.ZERO)
			var preferred_level := int(preferred.get("level", -1))
			var preferred_is_candidate := false
			for candidate in candidates:
				if candidate.get("cell", Vector2i(-1, -1)) == preferred_cell \
						and int(candidate.get("level", -1)) == preferred_level:
					preferred_is_candidate = true
					break
			if preferred_is_candidate \
					and not occupied_by_other.has(
						_navigation_vertex_key(preferred_cell, preferred_level)):
				var preferred_plan: Dictionary = grid.find_multi_level_plan(
					actor_cell, actor_level, preferred_cell, preferred_level)
				if not preferred_plan.is_empty():
					return _navigation_location_from_vertex(grid, preferred)

	var best: Dictionary = {}
	var best_cost := INF
	for candidate in candidates:
		var cell: Vector2i = candidate.get("cell", Vector2i.ZERO)
		var level := int(candidate.get("level", -1))
		if occupied_by_other.has(_navigation_vertex_key(cell, level)):
			continue
		var plan: Dictionary = grid.find_multi_level_plan(
			actor_cell, actor_level, cell, level
		)
		if plan.is_empty():
			continue
		var cost := float(plan.get("total_cost", INF))
		if best.is_empty() or cost < best_cost - 0.0001:
			best = candidate
			best_cost = cost
	if best.is_empty():
		return {}
	return _navigation_location_from_vertex(grid, best)


static func _navigation_region_vertex(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var raw := value as Dictionary
	var cell_v: Variant = raw.get("cell", null)
	var cell: Vector2i
	if cell_v is Vector2i:
		cell = cell_v as Vector2i
	elif cell_v is Array and (cell_v as Array).size() >= 2:
		cell = Vector2i(int(cell_v[0]), int(cell_v[1]))
	else:
		return {}
	if not raw.has("level"):
		return {}
	return {"cell": cell, "level": int(raw.get("level", -1))}


static func _navigation_location_from_vertex(grid, vertex: Dictionary) -> Dictionary:
	var cell: Vector2i = vertex.get("cell", Vector2i.ZERO)
	var level := int(vertex.get("level", 0))
	return {
		"cell": cell,
		"level": level,
		"data_position": grid.grid_to_world(cell, level),
		"graph_revision": grid.get_path_walkability_revision(),
		"interaction_region": true,
	}


static func _navigation_vertex_key(cell: Vector2i, level: int) -> String:
	return "%d:%d:%d" % [level, cell.x, cell.y]


func _interaction_target_owners(target: Node) -> Array[Node]:
	var owners: Array[Node] = []
	if target == null:
		return owners
	if target.has_method("get_interaction_delegate"):
		var delegate_v: Variant = target.call("get_interaction_delegate")
		if delegate_v is Node and is_instance_valid(delegate_v):
			owners.append(delegate_v as Node)
	if not owners.has(target):
		owners.append(target)
	return owners


## Pure/read-only semantic route gate. The servicing actor has already been
## selected deterministically, but no navigation command or presentation has
## occurred when this function runs.
func _target_interaction_route_preflight(
		target: Node, interactor_id: String
	) -> Dictionary:
	for owner in _interaction_target_owners(target):
		if not owner.has_method("get_interaction_route_preflight"):
			continue
		var result_v: Variant = owner.call(
			"get_interaction_route_preflight", interactor_id)
		if result_v is Dictionary:
			var result := (result_v as Dictionary).duplicate(true)
			if not result.has("accepted"):
				result["accepted"] = false
			return result
		return {
			"accepted": false,
			"code": "invalid_route_preflight",
			"message": "That object's route contract is unavailable.",
			"cue": "RESOLVE FIRST // ROUTE CONTRACT UNAVAILABLE",
		}
	return {"accepted": true, "code": ""}


func _present_target_interaction_route_refusal(
		target: Node, interactor_id: String, result: Dictionary
	) -> bool:
	for owner in _interaction_target_owners(target):
		if owner.has_method("present_interaction_route_refusal"):
			owner.call(
				"present_interaction_route_refusal",
				interactor_id,
				result.duplicate(true)
			)
			return true
	return false


func _target_navigation_region(target: Node) -> Dictionary:
	if target == null:
		return {}
	for owner in _interaction_target_owners(target):
		if owner.has_method("get_interaction_navigation_region"):
			var published_v: Variant = owner.call(
				"get_interaction_navigation_region")
			if published_v is Dictionary \
					and not (published_v as Dictionary).is_empty():
				return (published_v as Dictionary).duplicate(true)
		if owner.has_meta("interaction_navigation_region"):
			var region_v: Variant = owner.get_meta("interaction_navigation_region")
			if region_v is Dictionary:
				return (region_v as Dictionary).duplicate(true)
	return {}


func _navigation_region_contains(cell: Vector2i, level: int) -> bool:
	if _navigation_region_contract.is_empty():
		return false
	for vertex_v in _navigation_region_contract.get("region_vertices", []):
		var vertex := _navigation_region_vertex(vertex_v)
		if not vertex.is_empty() \
				and int(vertex.get("level", -1)) == level \
				and vertex.get("cell", Vector2i(-1, -1)) == cell:
			return true
	return false

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
	_queue_arrival_poll()


func _queue_arrival_poll() -> void:
	if active_target == null:
		return
	var generation := _target_generation
	if _pending_arrival_poll_generation == generation:
		return
	_pending_arrival_poll_generation = generation
	call_deferred("_deferred_arrival_poll", generation)


func _deferred_arrival_poll(generation: int) -> void:
	if _pending_arrival_poll_generation == generation:
		_pending_arrival_poll_generation = -1
	if generation != _target_generation or active_target == null:
		return
	_poll_arrival()

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
		_request_owner_id = ""
		_navigation_target.clear()
		_navigation_region_contract.clear()
		return
	# THE CLICK KEEPS ITS PROMISE: "stopped moving" is not "arrived". A wash
	# sweep / knockback / ride SUPERSEDES the committed walk and dumps the
	# servicer elsewhere — mid-carry we wait, and a landing outside the
	# target's reach RE-DRIVES the same commitment (bounded) instead of
	# completing at the wrong spot, where a strict validator truthfully
	# refuses and the player's click dies silently (the wash_ascent flure
	# contract catch).
	var gs_arr = _character_game_state()
	if _interactor_id != "" and gs_arr != null \
			and gs_arr.characters.has(_interactor_id) \
			and _flat_target != Vector3.INF:
		if gs_arr.has_method("is_external_traversal_active") \
				and bool(gs_arr.is_external_traversal_active(_interactor_id)):
			return
		var at: Vector3 = gs_arr.get_position(_interactor_id)
		var reached_navigation_target := true
		if not _navigation_region_contract.is_empty() \
				and gs_arr.has_method("get_character_level") \
				and "grid" in gs_arr and gs_arr.grid != null:
			reached_navigation_target = _navigation_region_contains(
				gs_arr.grid.world_to_grid(at),
				int(gs_arr.get_character_level(_interactor_id))
			)
		elif not _navigation_target.is_empty():
			var target_cell_v: Variant = _navigation_target.get("cell", null)
			var target_level := int(_navigation_target.get("level", -1))
			reached_navigation_target = target_cell_v is Vector2i \
				and gs_arr.has_method("get_character_level") \
				and int(gs_arr.get_character_level(_interactor_id)) == target_level
			if reached_navigation_target and "grid" in gs_arr \
					and gs_arr.grid != null:
				reached_navigation_target = gs_arr.grid.world_to_grid(at) \
					== (target_cell_v as Vector2i)
		var reached_physical_target := reached_navigation_target
		if _navigation_region_contract.is_empty():
			reached_physical_target = reached_physical_target \
				and Vector2(at.x, at.z).distance_to(
					Vector2(_flat_target.x, _flat_target.z)) <= _arrival_reach
		if not reached_physical_target:
			if _redrive_count < _MAX_REDRIVES:
				_redrive_count += 1
				if _drive_interactor_to(active_target_position, _flat_target):
					return
			_refuse_active_target("No reachable interaction point at that object.")
			return
	var completed := active_target
	var published_owner_before_arrival := _target_active_character(completed)
	if published_owner_before_arrival == "":
		published_owner_before_arrival = _request_owner_id
	# Selection can change while a character is walking. Reassert the servicing body at arrival so
	# a global portrait update cannot make a required-character action complete as somebody else.
	_set_target_active_character(completed, _interactor_id)
	if not _target_feedback_is_managed(completed) and completed.has_method("complete_queued_feedback"):
		completed.call("complete_queued_feedback")
	target_reached.emit(completed)
	if completed.has_method("on_interaction_arrived"):
		completed.call("on_interaction_arrived")
	# `active_character` is the public portrait selection outside the trigger
	# stack. Restore the value that was current immediately before servicing so a
	# repeat click is still owned by the selected body, not by the prior servicer.
	if is_instance_valid(completed) and published_owner_before_arrival != "":
		_set_target_active_character(completed, published_owner_before_arrival)
	active_target = null
	_interactor_id = ""
	_request_owner_id = ""
	_navigation_target.clear()
	_navigation_region_contract.clear()


func _refuse_active_target(
		reason: String, route_preflight: Dictionary = {}
	) -> void:
	var refused := active_target
	if refused != null and is_instance_valid(refused):
		if not _target_feedback_is_managed(refused) \
				and refused.has_method("cancel_queued_feedback"):
			refused.call("cancel_queued_feedback")
		# Exhausting the bounded routed approach is an authoritative result for the
		# exact object the player clicked. Finish its queued glow with the same red
		# target pulse used by a trigger preflight rejection; the HUD reason remains
		# a fallback, not the only evidence that the click was refused. Draw this
		# receipt before scenario presentation is allowed to focus a prerequisite:
		# otherwise a same-stack camera move can make the clicked result impossible
		# for either a human or a screen-observing persona to witness.
		if refused.has_method("play_interaction_result"):
			refused.call("play_interaction_result", false)
		if not route_preflight.is_empty():
			_present_target_interaction_route_refusal(
				refused, _interactor_id, route_preflight)
		target_cancelled.emit(refused)
	active_target = null
	_interactor_id = ""
	_request_owner_id = ""
	_navigation_target.clear()
	_navigation_region_contract.clear()
	_target_generation += 1
	if character != null and character.has_method("present_move_refusal"):
		character.call("present_move_refusal", reason)

func _target_feedback_is_managed(target: Node) -> bool:
	return target != null and target.has_method("is_feedback_managed") and bool(target.call("is_feedback_managed"))

func _character_can_accept_interaction() -> bool:
	if character == null:
		return false
	if character.has_method("is_move_enabled"):
		return bool(character.call("is_move_enabled"))
	var enabled = character.get("_move_enabled")
	return true if enabled == null else bool(enabled)


## Only one per-character coordinator may consume a shared target signal. Live
## targets latch an immutable owner for the synchronous command delivery;
## isolated/single-character scenes fall back to the move-input ownership gate.
func _controller_owns_request(target: Node) -> bool:
	var owner_id := _target_interaction_request_owner(target)
	if owner_id != "":
		return owner_id == _self_id()
	return _character_can_accept_interaction()


func _target_interaction_request_owner(target: Node) -> String:
	for owner in _interaction_target_owners(target):
		if owner.has_method("get_interaction_request_owner"):
			var owner_id := str(owner.call("get_interaction_request_owner"))
			if owner_id != "":
				return owner_id
	return _target_active_character(target)


func _target_active_character(target: Node) -> String:
	for owner in _interaction_target_owners(target):
		if "active_character" in owner:
			var owner_id := str(owner.get("active_character"))
			if owner_id != "":
				return owner_id
	return ""


## A newer accepted interaction for the same servicing body explicitly
## supersedes an older coordinator's commitment. Without this handshake, two
## per-character controllers can alternately redrive that body toward stale
## targets after portrait selection changes.
func _cancel_peer_commands_for_interactor(interactor_id: String) -> void:
	if interactor_id == "" or not is_inside_tree():
		return
	var gs = _character_game_state()
	for peer_v in get_tree().get_nodes_in_group(_CONTROLLER_GROUP):
		if peer_v == self or not (peer_v is CharacterInteractionController):
			continue
		var peer := peer_v as CharacterInteractionController
		if peer._character_game_state() == gs:
			peer.cancel_servicing_interactor(interactor_id)


func cancel_servicing_interactor(interactor_id: String) -> void:
	if active_target != null and _interactor_id == interactor_id:
		cancel_active_target()


func _interactor_can_accept_interaction(interactor_id: String) -> bool:
	if interactor_id == "":
		return false
	var gs = _character_game_state()
	if gs != null and gs.has_method("can_accept_move_command"):
		return bool(gs.call("can_accept_move_command", interactor_id))
	return interactor_id == _self_id() and _character_can_accept_interaction()

func _character_position() -> Vector3:
	if character == null:
		return Vector3.ZERO
	var game_state = character.get("game_state")
	var char_id := str(character.get("char_id"))
	if game_state != null and char_id != "" and game_state.characters.has(char_id):
		return game_state.get_position(char_id)
	return character.global_position
