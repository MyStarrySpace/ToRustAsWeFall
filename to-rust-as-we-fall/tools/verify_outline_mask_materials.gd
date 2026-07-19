extends SceneTree

## Focused regression for generated-target hover. A generated PrimitiveMesh commonly
## carries only a MeshInstance3D override (or no material at all); the outline mask
## must give its private copy an explicit surface material before the renderer sees it.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var manager := OutlineMaskManager.new()
	host.add_child(manager)
	var source := MeshInstance3D.new()
	source.mesh = BoxMesh.new()
	# Deliberately leave both mesh.material and material_override null.
	host.add_child(source)
	manager.register(41, [source], Color(0.95, 0.95, 1.0), true)
	await process_frame
	await process_frame

	var entries: Dictionary = manager.get("_entries")
	var entry: Dictionary = entries.get(41, {})
	var copies: Array = entry.get("copies", [])
	var valid := copies.size() == 1
	if valid:
		var copy := copies[0].get("copy", null) as MeshInstance3D
		valid = (
			copy != null
			and copy.mesh is PrimitiveMesh
			and (copy.mesh as PrimitiveMesh).material is ShaderMaterial
			and copy.get_surface_override_material(0) is ShaderMaterial
		)
	manager.unregister(41)
	host.queue_free()
	await process_frame
	if valid:
		print("PASS: outline mask copies always own a non-null fill material")
		quit(0)
	else:
		push_error("Outline mask copy did not receive an explicit fill material")
		quit(1)
