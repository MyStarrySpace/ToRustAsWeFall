class_name PushTarget
extends StaticBody3D

## Pickable wrapper over a PUSHABLE physics object's mesh: a `command` (right) click on it asks the
## scene to QUEUE a push for that object (the BG3-style plan-then-commit flow). The wrapper only
## reports intent; the player/preview owns the queue, the ghosts, and the commit.
##
## The crate speaks the shared hover grammar: it emits outline_hovered/outline_unhovered (so the
## scene's OutlineFeedbackManager binds it like any interactable), carries the "PUSH" cursor verb,
## and forwards highlight requests to a NON-pickable OutlineSurfaceTarget wrapping the crate mesh —
## the PushTarget body stays the ONE pickable node, so the physics ray never flips between two
## competing bodies.

signal push_queue_requested(obj_id: String)
signal outline_hovered(target: Node)
signal outline_unhovered(target: Node)

const OutlineTargetScript := preload("res://scripts/game/objects/outline_surface_target.gd")

var obj_id := ""
var _outline_target: Node = null

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	input_ray_pickable = true
	add_to_group("push_targets")
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

## Wrap an existing mesh with a pickable box matching its AABB, plus the outline surface that
## renders the crate's hover/reveal silhouette.
static func wrap(mesh: MeshInstance3D, id: String) -> PushTarget:
	var t := PushTarget.new()
	t.name = "PushTarget_" + id
	t.obj_id = id
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (mesh.mesh.get_aabb().size if mesh.mesh != null else Vector3.ONE) + Vector3(0.1, 0.1, 0.1)
	shape.shape = box
	t.add_child(shape)
	mesh.add_child(t)
	var outline := OutlineTargetScript.new()
	outline.name = "PushOutline_" + id
	outline.hover_enabled = false
	mesh.add_child(outline)
	outline.register_highlight_mesh(mesh)
	outline.set_interaction_delegate(t)
	t._outline_target = outline
	return t

## The cursor verb the hover grammar shows for a pushable crate.
func get_action_verb() -> String:
	return "PUSH"

## Hover and the hold-SHIFT reveal both light the crate's outline — the shared grammar.
func set_hover_feedback(active: bool) -> void:
	if _outline_target != null and is_instance_valid(_outline_target):
		_outline_target.set_highlight(active)

func set_highlight(active: bool) -> void:
	set_hover_feedback(active)

func get_outline_target() -> Node:
	return _outline_target

func _on_mouse_entered() -> void:
	outline_hovered.emit(self)

func _on_mouse_exited() -> void:
	outline_unhovered.emit(self)

func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if event is InputEventMouseButton and event.is_action_pressed("command"):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		push_queue_requested.emit(obj_id)
