class_name PushTarget
extends StaticBody3D

## Pickable wrapper over a PUSHABLE physics object's mesh: a `command` (right) click on it asks the
## scene to QUEUE a push for that object (the BG3-style plan-then-commit flow). Mirrors
## OutlineSurfaceTarget's input pattern — the wrapper only reports intent; the player/preview owns
## the queue, the ghosts, and the commit.

signal push_queue_requested(obj_id: String)

var obj_id := ""

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	input_ray_pickable = true
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)

## Wrap an existing mesh with a pickable box matching its AABB.
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
	return t

func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if event is InputEventMouseButton and event.is_action_pressed("command"):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		push_queue_requested.emit(obj_id)
