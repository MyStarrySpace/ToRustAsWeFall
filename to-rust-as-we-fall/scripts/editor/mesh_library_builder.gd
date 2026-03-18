@tool
extends Node

## Run this once in the editor to generate the MeshLibrary resource.
## Attach to any node, toggle `generate` in the inspector, then remove.

@export var generate: bool = false:
	set(value):
		if value:
			_build_library()
		generate = false

func _build_library() -> void:
	var lib := MeshLibrary.new()

	# Item 0: basic 1x1x1 box
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	lib.create_item(0)
	lib.set_item_mesh(0, box)
	lib.set_item_name(0, "block")

	# Give it a simple shape for raycasting / collision
	var shape := BoxShape3D.new()
	shape.size = Vector3(1, 1, 1)
	var shape_array: Array[Transform3D] = [Transform3D.IDENTITY]

	lib.set_item_shapes(0, [shape, Transform3D.IDENTITY])

	var err := ResourceSaver.save(lib, "res://resources/block_library.tres")
	if err == OK:
		print("MeshLibrary saved to res://resources/block_library.tres")
	else:
		push_error("Failed to save MeshLibrary: %s" % err)
