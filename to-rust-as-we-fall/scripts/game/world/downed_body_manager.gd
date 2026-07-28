class_name DownedBodyManager
extends Node3D

## Downed characters become INTERACTABLE bodies: click one to CARRY them (the shared drag system —
## both hands, slower, stamina burn while moving), click the carried body again to set it down.
## One per scene, created by tutorial_sequence like PathRenderManager, listening to the GameState
## downed/restored signals — so retrieval works identically in EVERY scene, never per-chunk.
##
## The body zone is a normal INSPECTION Interactable (click → the servicing member walks over →
## fires on arrival, inside the drag pickup radius) and it RIDES the body — a carried friend stays
## clickable at the carrier's heel. Hover shows the fallen character's real silhouette through the
## shared outline system when their scene node has meshes.
##
## Body Areas and outline targets are prepared one per rendered frame while the party is healthy.
## A lethal stat write must not allocate physics/UI nodes or scan a large scene tree synchronously.

var _gs
var _search_root: Node
var _bodies := {}          # active/downed char_id -> Interactable
var _prepared_bodies := {} # char_id -> disabled pooled Interactable (also includes active bodies)
var _outline_targets := {} # char_id -> pooled OutlineSurfaceTarget
var _prepare_queue: Array[Dictionary] = []
var _queued_ids := {}

const SYNC_TICK := 0.2

func setup(state, root: Node = null) -> void:
	_gs = state
	_search_root = root if root != null else self
	if _gs == null:
		return
	if not _gs.character_downed.is_connected(_on_character_downed):
		_gs.character_downed.connect(_on_character_downed)
	if not _gs.character_restored.is_connected(_on_character_up):
		_gs.character_restored.connect(_on_character_up)
	if not _gs.character_revived.is_connected(_on_character_up):
		_gs.character_revived.connect(_on_character_up)
	if _search_root != null and _search_root.has_method("get_game_state_character_nodes"):
		var registered: Dictionary = _search_root.call("get_game_state_character_nodes")
		for raw_id in registered.keys():
			prepare_character(str(raw_id), registered[raw_id])

func _process(_delta: float) -> void:
	_prepare_next_body()
	_sync_bodies()   # live smoothness; the DATA truth rides the scheduler tick below

## Add a newly registered controllable character to the staged prewarm queue.
## Enemies and lightweight NPCs are GameState characters too, but only player
## bodies participate in the carry/revive interaction.
func prepare_character(cid: String, node: Node3D) -> void:
	if cid == "" or node == null or not is_instance_valid(node) or node is Enemy \
			or not (node is CharacterBody3D) or _prepared_bodies.has(cid) or _queued_ids.has(cid):
		return
	_prepare_queue.append({"id": cid, "node": node})
	_queued_ids[cid] = true

func _prepare_next_body() -> void:
	if _prepare_queue.is_empty():
		return
	var entry: Dictionary = _prepare_queue.pop_front()
	var cid := str(entry.get("id", ""))
	_queued_ids.erase(cid)
	var node = entry.get("node")
	if cid != "" and node is Node3D and is_instance_valid(node):
		_prepare_body(cid, node as Node3D)

func has_prepared_body(cid: String) -> bool:
	return _prepared_bodies.has(cid) and is_instance_valid(_prepared_bodies[cid])

func get_prepared_body(cid: String) -> Interactable:
	var body = _prepared_bodies.get(cid)
	return body as Interactable if body is Interactable and is_instance_valid(body) else null

## The zone rides the body (a carried friend moves) and the verb reads the carry state. Runs BOTH
## per-frame (live) and on a scheduler tick — so a headless test that jumps the scheduler without
## rendering a single frame still sees the zone where the body is. That is the architecture's
## promise: simulated time behaves exactly like waited time, minus the waiting.
func _sync_bodies() -> void:
	for cid in _bodies.keys():
		var it = _bodies[cid]
		if not is_instance_valid(it) or _gs == null or not _gs.characters.has(str(cid)):
			continue
		it.position = _gs.get_position(str(cid))
		var carried: bool = _gs.get_dragger_of(str(cid)) != ""
		it.description = ("Set %s down" if carried else "Carry %s") % str(cid).capitalize()

func _arm_sync_tick() -> void:
	if _gs == null or _gs.scheduler == null:
		return
	_gs.scheduler.cancel_tag("downed_body_sync")
	_gs.scheduler.schedule_after(SYNC_TICK, _on_sync_tick, "downed_body_sync")

func _on_sync_tick() -> void:
	_sync_bodies()
	if not _bodies.is_empty():
		_arm_sync_tick()

func _on_character_downed(cid: String) -> void:
	var perf_started := PerformanceTrace.begin()
	if _gs == null or _bodies.has(cid):
		PerformanceTrace.end(&"update", &"downed_body.activate", perf_started, cid, 0)
		return
	var it := get_prepared_body(cid)
	if it == null:
		# Compatibility for a character registered/downed before a render frame had
		# a chance to drain the queue. The host registry keeps this O(1).
		var node := _find_char_node(cid)
		if node is Enemy or node == null:
			PerformanceTrace.end(&"update", &"downed_body.activate", perf_started, cid, 0)
			return
		_prepare_body(cid, node)
		it = get_prepared_body(cid)
	if it == null:
		PerformanceTrace.end(&"update", &"downed_body.activate", perf_started, cid, 0)
		return
	_activate_body(cid, it)
	PerformanceTrace.end(&"update", &"downed_body.activate", perf_started, cid, 1)

func _prepare_body(cid: String, node: Node3D) -> void:
	if has_prepared_body(cid):
		return
	var perf_started := PerformanceTrace.begin()
	var it := Interactable.new()
	it.name = "PreparedDownedBody_%s" % cid
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var sh := SphereShape3D.new()
	sh.radius = 1.3
	cs.shape = sh
	it.add_child(cs)
	it.interaction_radius = 1.3
	it.interactable_type = Interactable.InteractableType.INSPECTION
	it.one_shot = false
	it.description = "Carry %s" % cid.capitalize()
	it.tutorial_label = "CARRY"
	it.interaction_enabled = false
	var tree_entry_started := PerformanceTrace.begin()
	add_child(it)
	PerformanceTrace.end(&"draw", &"downed_body.tree_entry", tree_entry_started, cid, 1)
	it.set_interaction_enabled(false)
	if _gs != null and _gs.characters.has(cid):
		it.position = _gs.get_position(cid)
	it.interacted.connect(_on_body_clicked.bind(cid))
	var outline_started := PerformanceTrace.begin()
	_wire_body_outline(it, cid, node)
	PerformanceTrace.end(&"draw", &"downed_body.outline", outline_started, cid,
		int(_outline_targets.has(cid)))
	_prepared_bodies[cid] = it
	PerformanceTrace.end(&"draw", &"downed_body.prepare", perf_started, cid, 1)

func _activate_body(cid: String, it: Interactable) -> void:
	it.name = "DownedBody_%s" % cid
	it.position = _gs.get_position(cid)
	it.set_interaction_enabled(true)
	_set_outline_pickable(cid, true)
	# Register with the host like any chunk interactable — this wires click
	# servicing, hover feedback, the scheduler, and active-character sync.
	if _search_root != null and is_instance_valid(_search_root) \
			and _search_root.has_method("register_preview_interactable"):
		var registration_started := PerformanceTrace.begin()
		_search_root.call("register_preview_interactable", it)
		PerformanceTrace.end(&"update", &"downed_body.register_interactable",
			registration_started, cid, 1)
	_bodies[cid] = it
	_arm_sync_tick()

## Hover lights the fallen character's REAL body mesh through the shared outline
## system. A character can expose its explicit body meshes so path previews,
## ability markers, and other utility descendants never become part of the body.
func _wire_body_outline(it: Interactable, cid: String, node: Node3D) -> void:
	if node == null:
		return
	var meshes: Array = []
	if node.has_method("get_downed_outline_meshes"):
		for mesh in node.call("get_downed_outline_meshes"):
			meshes.append(mesh)
	else:
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			meshes.append(mesh)
	if meshes.is_empty():
		return
	var mgr := OutlineFeedbackManager.ensure(self)
	if mgr == null:
		return
	var target := mgr.outline_meshes(node, "DownedOutline_%s" % cid, meshes,
		"downed_" + cid, 1.3, {"hover_enabled": false})
	if target == null:
		return
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", it)
	it.set_outline_target(target)
	_outline_targets[cid] = target

func _set_outline_pickable(cid: String, active: bool) -> void:
	var target = _outline_targets.get(cid)
	if target == null or not is_instance_valid(target):
		return
	if not active and target.has_method("set_hover_feedback"):
		target.call("set_hover_feedback", false)
	target.set("hover_enabled", active)
	target.set("collision_layer", 4 if active else 0)
	target.set("input_ray_pickable", active)

func _on_body_clicked(cid: String) -> void:
	if _gs == null or not _bodies.has(cid):
		return
	var it = _bodies[cid]
	var interactor := str(it.active_character) if is_instance_valid(it) else ""
	if interactor == "" or not _gs.characters.has(interactor) or _gs.is_downed(interactor):
		return
	var dragger: String = _gs.get_dragger_of(cid)
	if dragger != "":
		if dragger == interactor:
			_gs.command_stop_drag(interactor)
		return
	if not _gs.has_free_hands(interactor, 2):
		_toast("Both hands must be free to carry %s." % cid.capitalize())
		return
	if not _gs.command_start_drag(interactor, cid):
		_toast("Can't take hold from here.")

func _on_character_up(cid: String) -> void:
	if not _bodies.has(cid):
		return
	var it = _bodies[cid]
	if is_instance_valid(it):
		it.set_interaction_enabled(false)
		it.name = "PreparedDownedBody_%s" % cid
	_set_outline_pickable(cid, false)
	_bodies.erase(cid)

func _exit_tree() -> void:
	if _gs != null and _gs.scheduler != null:
		_gs.scheduler.cancel_tag("downed_body_sync")

func _toast(text: String) -> void:
	if _search_root != null and is_instance_valid(_search_root) \
			and _search_root.has_method("show_preview_message"):
		_search_root.call("show_preview_message", text, 2.0)

func _find_char_node(char_id: String) -> Node3D:
	if _search_root == null or not is_instance_valid(_search_root):
		return null
	if _search_root.has_method("get_game_state_character_node"):
		return _search_root.call("get_game_state_character_node", char_id) as Node3D
	if _search_root.has_method("get_preview_character_node"):
		return _search_root.call("get_preview_character_node", char_id) as Node3D
	for node in _search_root.find_children("*", "", true, false):
		if node == self or is_ancestor_of(node):
			continue
		if node is Node3D and "char_id" in node and str(node.char_id) == char_id:
			return node
	return null
