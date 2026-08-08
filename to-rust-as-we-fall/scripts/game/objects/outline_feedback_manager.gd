class_name OutlineFeedbackManager
extends Node

## Owns hover and selected feedback for outline-capable targets, AND builds the
## outline-target representations themselves. Any scene or chunk calls
## OutlineFeedbackManager.ensure(self) to get the shared system for its branch and
## outline an object's meshes — the same path works in tutorials and in gameplay
## chunks (an outline target without a manager silently does nothing).

const OUTLINE_TARGET_SCRIPT := preload("res://scripts/game/objects/outline_surface_target.gd")
const CURSOR_VERB_SCENE := preload("res://scenes/ui/cursor_verb.tscn")

## Default OutlineSurfaceTarget tuning; a per-call opts dict overrides individual keys.
const OUTLINE_DEFAULTS := {
	"outline_highlight_height": 0.0,
	"selected_feedback_duration": 3.0,
	"hover_object_outline_width": 0.012,
	"selected_object_outline_width": 0.02,
	"selected_object_glow_strength": 3.8,
	"selected_particle_count": 180,
	"outline_particles_enabled": true,
	"outline_particles_per_mesh": 220,
}

## Canonical object-level events for systems that augment hover/selection (causal
## links, contextual help, accessibility reads). Consumers receive the interaction
## delegate even when the physics ray alternates between its Area and surface body.
signal hovered_target_changed(target: Node)
signal selected_target_changed(target: Node)

var hovered_target: Node = null
var selected_target: Node = null

var _bound_targets := {}
var _bound_controllers := {}
var _selection_token := 0

func bind_target(target: Node) -> void:
	if target == null:
		return
	var has_feedback_signal := target.has_signal("outline_hovered") or target.has_signal("outline_selected")
	if not has_feedback_signal:
		return
	var target_id := target.get_instance_id()
	if _bound_targets.has(target_id):
		return
	_bound_targets[target_id] = target
	if target.has_method("set_feedback_managed"):
		target.call("set_feedback_managed", true)
	if target.has_signal("outline_hovered") and not target.is_connected("outline_hovered", _on_target_hovered):
		target.connect("outline_hovered", _on_target_hovered)
	if target.has_signal("outline_unhovered") and not target.is_connected("outline_unhovered", _on_target_unhovered):
		target.connect("outline_unhovered", _on_target_unhovered)
	if target.has_signal("outline_selected") and not target.is_connected("outline_selected", _on_target_selected):
		target.connect("outline_selected", _on_target_selected)
	if target.is_inside_tree():
		target.tree_exiting.connect(_on_bound_target_exiting.bind(target_id), CONNECT_ONE_SHOT)

func bind_interaction_controller(controller: Node) -> void:
	if controller == null:
		return
	if not controller.has_signal("target_reached") and not controller.has_signal("target_cancelled"):
		return
	var controller_id := controller.get_instance_id()
	if _bound_controllers.has(controller_id):
		return
	_bound_controllers[controller_id] = controller
	if controller.has_signal("target_reached") and not controller.is_connected("target_reached", _on_controller_target_reached):
		controller.connect("target_reached", _on_controller_target_reached)
	if controller.has_signal("target_cancelled") and not controller.is_connected("target_cancelled", _on_controller_target_cancelled):
		controller.connect("target_cancelled", _on_controller_target_cancelled)
	if controller.is_inside_tree():
		controller.tree_exiting.connect(_on_bound_controller_exiting.bind(controller_id), CONNECT_ONE_SHOT)


func _on_bound_target_exiting(target_id: int) -> void:
	var target = _bound_targets.get(target_id, null)
	var canon := _canonical_target(target)
	if hovered_target == target or hovered_target == canon:
		hovered_target = null
		_hide_cursor_verb()
		hovered_target_changed.emit(null)
	if selected_target == target or selected_target == canon:
		selected_target = null
		_selection_token += 1
	_bound_targets.erase(target_id)


func _on_bound_controller_exiting(controller_id: int) -> void:
	_bound_controllers.erase(controller_id)

func get_hovered_target() -> Node:
	return hovered_target

func get_selected_target() -> Node:
	return selected_target

## An object is TWO pickable nodes — the meshless Interactable Area and its OutlineSurfaceTarget
## body wrapping the visible meshes — and the physics pick flips between them as the camera eases.
## Resolve every hover to the CANONICAL node (the surface target's interaction delegate, i.e. the
## interactable) so a flip is a no-op: no unhover/rehover churn, the outline holds, the cursor verb
## doesn't flicker out whenever the body wins the ray.
func _canonical_target(target: Node) -> Node:
	if target != null and is_instance_valid(target) and target.has_method("get_interaction_delegate"):
		var delegate = target.call("get_interaction_delegate")
		if delegate is Node and is_instance_valid(delegate):
			return delegate
	return target

func _on_target_hovered(target: Node) -> void:
	var canon := _canonical_target(target)
	if hovered_target == canon:
		return
	if hovered_target != null and is_instance_valid(hovered_target):
		_set_hover_feedback(hovered_target, false)
	hovered_target = canon
	_set_hover_feedback(canon, true)
	_show_cursor_verb(canon)
	hovered_target_changed.emit(canon)

func _on_target_unhovered(target: Node) -> void:
	if hovered_target != _canonical_target(target):
		return
	if hovered_target != null and is_instance_valid(hovered_target):
		_set_hover_feedback(hovered_target, false)
	hovered_target = null
	_hide_cursor_verb()
	hovered_target_changed.emit(null)

# --- the CURSOR VERB: the hovered interactable's action verb, ONE line, riding above the mouse.
# Cosmetic UI (wall-clock per-frame follow is fine — it renders, it never touches game state). ---

var _cursor_verb: Label = null

func _ensure_cursor_verb() -> void:
	if _cursor_verb != null and is_instance_valid(_cursor_verb):
		return
	var layer := CURSOR_VERB_SCENE.instantiate() as CanvasLayer
	add_child(layer)
	_cursor_verb = layer.get_node("CursorVerb") as Label

func _show_cursor_verb(target: Node) -> void:
	_ensure_cursor_verb()
	var verb := ""
	var preview := ""
	if target != null and is_instance_valid(target) and target.has_method("get_action_verb"):
		verb = str(target.call("get_action_verb"))
	if target != null and is_instance_valid(target) and target.has_method("get_action_preview"):
		preview = str(target.call("get_action_preview")).strip_edges()
	_cursor_verb.text = verb + ("\n-> %s" % preview if preview != "" else "")
	_cursor_verb.visible = verb != ""
	if _cursor_verb.visible:
		set_process(true)
		_follow_mouse()

func _hide_cursor_verb() -> void:
	if _cursor_verb != null and is_instance_valid(_cursor_verb):
		_cursor_verb.visible = false
	set_process(false)

func _process(_delta: float) -> void:
	_follow_mouse()

func _follow_mouse() -> void:
	if _cursor_verb == null or not is_instance_valid(_cursor_verb) or not _cursor_verb.visible:
		return
	var mp := get_viewport().get_mouse_position()
	# Keep the consequence beside the cursor instead of centering a wide two-line label
	# over the cause, its target, and the relationship we are trying to explain.
	var viewport_size := get_viewport().get_visible_rect().size
	var desired := mp + Vector2(18.0, 18.0)
	if desired.x + _cursor_verb.size.x > viewport_size.x - 12.0:
		desired.x = mp.x - _cursor_verb.size.x - 18.0
	if desired.y + _cursor_verb.size.y > viewport_size.y - 12.0:
		desired.y = mp.y - _cursor_verb.size.y - 18.0
	_cursor_verb.position = Vector2(
		clampf(desired.x, 12.0, maxf(12.0, viewport_size.x - _cursor_verb.size.x - 12.0)),
		clampf(desired.y, 12.0, maxf(12.0, viewport_size.y - _cursor_verb.size.y - 12.0))
	)

func _on_target_selected(target: Node) -> void:
	if target == null:
		return
	selected_target_changed.emit(_canonical_target(target))
	if selected_target != null and selected_target != target and is_instance_valid(selected_target):
		_cancel_selected(selected_target)
	selected_target = target
	_selection_token += 1
	if target.has_method("begin_queued_feedback"):
		target.call("begin_queued_feedback", Vector3.ZERO, _queued_color_for(target))
	if not _is_controller_tracking(target):
		var token := _selection_token
		var duration := _read_target_float(target, "selected_feedback_duration", 0.8)
		# node-bound tween (dies with the manager), and the lambda holds the target's ID, not
		# the node -- a captured node freed mid-window would make the engine error on the call
		# itself, before any is_instance_valid guard could run
		var target_id := target.get_instance_id()
		var expire := create_tween()
		expire.tween_interval(maxf(0.05, duration))
		expire.tween_callback(func():
			var t := instance_from_id(target_id) as Node
			if t != null and token == _selection_token and selected_target == t and not _is_controller_tracking(t):
				_complete_selected(t))

## The queued tint comes from whichever bound controller is servicing this target — the
## interactor's character color (the manager itself has no notion of characters).
func _queued_color_for(target: Node) -> Color:
	for controller in _bound_controllers.values():
		if controller is Node and is_instance_valid(controller) \
				and controller.get("active_target") == target and controller.has_method("_interactor_color"):
			return controller.call("_interactor_color")
	return Color(0, 0, 0, 0)

func _on_controller_target_reached(target: Node) -> void:
	if selected_target == target:
		_complete_selected(target)

func _on_controller_target_cancelled(target: Node) -> void:
	if selected_target == target:
		_cancel_selected(target)

func _set_hover_feedback(target: Node, active: bool) -> void:
	if target != null and is_instance_valid(target) and target.has_method("set_hover_feedback"):
		target.call("set_hover_feedback", active)

func _complete_selected(target: Node) -> void:
	if target != null and is_instance_valid(target) and target.has_method("complete_queued_feedback"):
		target.call("complete_queued_feedback")
	if selected_target == target:
		selected_target = null
		_selection_token += 1

func _cancel_selected(target: Node) -> void:
	if target != null and is_instance_valid(target) and target.has_method("cancel_queued_feedback"):
		target.call("cancel_queued_feedback")
	if selected_target == target:
		selected_target = null
		_selection_token += 1

func _is_controller_tracking(target: Node) -> bool:
	for controller in _bound_controllers.values():
		if not is_instance_valid(controller):
			continue
		if controller.get("active_target") == target:
			return true
	return false

func _read_target_float(target: Node, property_name: String, fallback: float) -> float:
	if target == null:
		return fallback
	var value = target.get(property_name)
	if value == null:
		return fallback
	return float(value)

# --- Discovery ---

## Find the outline system for `context`'s branch, or create one. Sequences and
## chunks call this instead of owning a manager directly: it walks up from the caller
## looking for an existing manager among each ancestor's children (so two scenes
## coexisting in one tree never share a system), and otherwise creates one on the
## caller's scene root. Returns null only for a null context.
static func ensure(context: Node) -> OutlineFeedbackManager:
	if context == null:
		return null
	var node := context
	while node != null:
		var found := _find_manager_child(node)
		if found != null:
			return found
		node = node.get_parent()
	var anchor: Node = context.owner if context.owner != null else context
	var manager := OutlineFeedbackManager.new()
	manager.name = "OutlineFeedbackManager"
	anchor.add_child(manager)
	return manager

static func _find_manager_child(node: Node) -> OutlineFeedbackManager:
	for child in node.get_children():
		if child is OutlineFeedbackManager:
			return child as OutlineFeedbackManager
	return null

# --- Outline-target builder (data -> representation) ---

## Build an OutlineSurfaceTarget around `meshes`, register them as highlight meshes,
## and bind it to this manager so its hover/selected feedback is live. `opts` overrides
## OUTLINE_DEFAULTS per key, plus two specials: "delegate" (set_interaction_delegate)
## and "metadata" (a dict of set_meta calls). Returns the target node.
func create_outline_target(
		parent: Node3D,
		target_name: String,
		center: Vector3,
		size: Vector3,
		meshes: Array,
		element_id: String,
		radius: float = 1.0,
		opts: Dictionary = {}
	) -> Node3D:
	var target := StaticBody3D.new()
	target.name = target_name
	target.set_script(OUTLINE_TARGET_SCRIPT)
	target.position = center
	target.set("outline_highlight_radius", radius)
	target.set("outline_highlight_extents", size * 0.5)
	var props := OUTLINE_DEFAULTS.duplicate()
	for key in opts.keys():
		if key == "delegate" or key == "metadata":
			continue
		props[key] = opts[key]
	for key in props.keys():
		target.set(key, props[key])
	target.set_meta("room_element_id", element_id)
	if opts.has("metadata") and opts["metadata"] is Dictionary:
		for meta_key in (opts["metadata"] as Dictionary).keys():
			target.set_meta(meta_key, opts["metadata"][meta_key])

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	collision_shape.shape = box
	target.add_child(collision_shape)
	parent.add_child(target)

	for mesh in meshes:
		if mesh is MeshInstance3D:
			target.call("register_highlight_mesh", mesh)
	if opts.has("delegate") and opts["delegate"] != null and target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", opts["delegate"])
	if not Engine.is_editor_hint():
		bind_target(target)
	return target

## Like create_outline_target but derives the enclosing box from the meshes' own
## world bounds, so callers don't hand-tune a size. Returns null if no usable mesh.
func outline_meshes(
		parent: Node3D,
		target_name: String,
		meshes: Array,
		element_id: String,
		radius: float = 1.0,
		opts: Dictionary = {},
		padding: float = 0.12
	) -> Node3D:
	var bounds := combined_bounds_in_space(meshes, parent)
	if bounds.size == Vector3.ZERO:
		return null
	var center := bounds.position + bounds.size * 0.5
	var size := bounds.size + Vector3.ONE * (padding * 2.0)
	return create_outline_target(parent, target_name, center, size, meshes, element_id, radius, opts)

## AABB enclosing `meshes` in `space`'s LOCAL coordinates.  outline_meshes creates
## its target as a child of `space`, so both center and size must be expressed in
## this coordinate system (world-space sizes are also wrong under rotation/scale).
static func combined_bounds_in_space(meshes: Array, space: Node3D) -> AABB:
	var bounds := AABB()
	var started := false
	var world_to_space := space.global_transform.affine_inverse()
	for mesh in meshes:
		if not (mesh is MeshInstance3D):
			continue
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		var mesh_to_space := world_to_space * mi.global_transform
		var local_bounds: AABB = mesh_to_space * mi.mesh.get_aabb()
		if not started:
			bounds = local_bounds
			started = true
		else:
			bounds = bounds.merge(local_bounds)
	return bounds

## World-space AABB enclosing every MeshInstance3D in `meshes` (empty if none).
static func combined_world_bounds(meshes: Array) -> AABB:
	var bounds := AABB()
	var started := false
	for mesh in meshes:
		if not (mesh is MeshInstance3D):
			continue
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		var world := mi.global_transform * mi.mesh.get_aabb()
		if not started:
			bounds = world
			started = true
		else:
			bounds = bounds.merge(world)
	return bounds

## Gather every MeshInstance3D at or under `node` (objects often nest their meshes).
static func collect_mesh_instances(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(collect_mesh_instances(child))
	return result
