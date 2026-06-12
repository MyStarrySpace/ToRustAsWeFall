@tool
extends EditorScenePostImport

## Wires material SIDECAR textures at IMPORT time, so a fresh DCC re-export self-heals instead of
## silently dropping its emissive/normal layers (the bug that shipped twice). For every material
## whose albedo texture is a file, looks for `<albedo>_emissive.png` / `<albedo>_normals.png`
## beside it and wires emission/normal mapping. The gltf JSON itself no longer needs hand-rewiring
## for Godot (tools/gltf_wire_material_sidecars.py remains for engines/tools that read the gltf).
## Point a model at this via its .import: import_script/path="res://tools/sidecar_material_import.gd"

const EMISSION_ENERGY := 2.5

func _post_import(scene: Node) -> Object:
	var wired := {}
	for mesh_instance in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or wired.has(mat.get_instance_id()):
				continue
			wired[mat.get_instance_id()] = true
			_wire_sidecars(mat)
	return scene

func _wire_sidecars(mat: BaseMaterial3D) -> void:
	if mat.albedo_texture == null:
		return
	var albedo_path := mat.albedo_texture.resource_path
	if albedo_path == "" or not albedo_path.contains("."):
		return  # embedded textures have no file path; those models keep gltf-level wiring
	var base := albedo_path.get_basename()
	var emissive_path := base + "_emissive.png"
	if FileAccess.file_exists(emissive_path):
		mat.emission_enabled = true
		mat.emission_texture = load(emissive_path)
		mat.emission = Color.WHITE
		mat.emission_energy_multiplier = EMISSION_ENERGY
	var normals_path := base + "_normals.png"
	if FileAccess.file_exists(normals_path):
		mat.normal_enabled = true
		mat.normal_texture = load(normals_path)
