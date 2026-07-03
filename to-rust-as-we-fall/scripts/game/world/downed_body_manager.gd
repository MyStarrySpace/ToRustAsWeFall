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

var _gs
var _search_root: Node
var _bodies := {}          # downed char_id -> Interactable
var _outline_targets := {} # downed char_id -> OutlineSurfaceTarget (freed with the body zone)

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

const SYNC_TICK := 0.2

func _process(_delta: float) -> void:
	_sync_bodies()   # live smoothness; the DATA truth rides the scheduler tick below

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
	if _gs == null or _bodies.has(cid):
		return
	var node := _find_char_node(cid)
	if node is Enemy:
		return   # fallen fauna are not friends to carry
	var it := Interactable.new()
	it.name = "DownedBody_%s" % cid
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
	add_child(it)
	it.position = _gs.get_position(cid)
	it.interacted.connect(_on_body_clicked.bind(cid))
	_wire_body_outline(it, cid, node)
	# Register with the host like any chunk interactable — this is what wires the REAL play paths:
	# click servicing (bind_interaction_target on every character), hover feedback, the scheduler,
	# and the active-character sync. A zone that skips this looks alive in tests and is dead in play.
	if _search_root != null and is_instance_valid(_search_root) and _search_root.has_method("register_preview_interactable"):
		_search_root.call("register_preview_interactable", it)
	_bodies[cid] = it
	_arm_sync_tick()

## Hover lights the fallen character's REAL silhouette (their scene node's meshes) through the shared
## outline system — the same grammar as every object. No meshes (headless / pure-data char) → the
## zone still works, only the visual is skipped.
func _wire_body_outline(it: Interactable, cid: String, node: Node3D) -> void:
	if node == null:
		return
	var meshes: Array = []
	for m in node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(m)
	if meshes.is_empty():
		return
	var mgr := OutlineFeedbackManager.ensure(self)
	if mgr == null:
		return
	var target := mgr.outline_meshes(node, "DownedOutline_%s" % cid, meshes, "downed_" + cid, 1.3)
	if target == null:
		return
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", it)
	it.set_outline_target(target)
	_outline_targets[cid] = target

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
		# queue_free is DEFERRED: the dying node holds its name until end of frame, and a fresh zone
		# created the same frame (revive -> reset -> re-down) would get auto-renamed past every
		# find_child lookup. Vacate the canonical name before letting go.
		it.name = str(it.name) + "_gone"
		it.queue_free()
	_bodies.erase(cid)
	var target = _outline_targets.get(cid)
	if target != null and is_instance_valid(target):
		target.queue_free()
	_outline_targets.erase(cid)

func _exit_tree() -> void:
	if _gs != null and _gs.scheduler != null:
		_gs.scheduler.cancel_tag("downed_body_sync")

func _toast(text: String) -> void:
	if _search_root != null and is_instance_valid(_search_root) and _search_root.has_method("show_preview_message"):
		_search_root.call("show_preview_message", text, 2.0)

func _find_char_node(char_id: String) -> Node3D:
	if _search_root == null or not is_instance_valid(_search_root):
		return null
	for n in _search_root.find_children("*", "", true, false):
		if n == self or is_ancestor_of(n):
			continue
		if n is Node3D and "char_id" in n and str(n.char_id) == char_id:
			return n
	return null
