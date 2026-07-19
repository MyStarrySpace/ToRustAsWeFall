extends SceneTree

## Repository-level guard for authored generator output. Final biome landmarks must be
## thin runtime wrappers around portable meshes; every canonical architecture specimen
## must also have a deterministic Blockbench-ready bake.

const BIOME_SOURCE := "res://tools/asset_sources/biome_landmarks_source.tscn"
const BUILDING_BAKER := "res://tools/bake_building_kit.gd"

var failures := 0


func _init() -> void:
	var biomes = load("res://scripts/generation/biomes.gd")
	_check(FileAccess.file_exists(BIOME_SOURCE), "Biome landmark bake source is retained")
	for biome_v in biomes.biome_ids():
		var biome_id := str(biome_v)
		var theme: Dictionary = biomes.theme_contract_for(biome_id)
		for definition_v in theme.get("landmarks", []):
			_check_definition(biome_id, definition_v as Dictionary)
		for setpiece_v in theme.get("route_setpieces", []):
			_check_definition(biome_id, setpiece_v as Dictionary)

	var builder = load("res://scripts/generation/base_shape_builder.gd")
	_check(FileAccess.file_exists(BUILDING_BAKER), "Canonical architecture has a deterministic bake tool")
	for kind_v in builder.BUILDINGS:
		var kind := str(kind_v)
		var model_path := "res://resources/models/generated-architecture/%s/%s_seed_0.obj" % [kind, kind]
		_check_portable_model(model_path, "architecture/%s" % kind, false, true)
	print("[GENERATED ASSETS] %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)


func _check_definition(biome_id: String, definition: Dictionary) -> void:
	var role := str(definition.get("id", "unnamed"))
	_check(str(definition.get("asset_contract", "")) == "editable_3d_v1",
		"%s/%s declares editable_3d_v1" % [biome_id, role])
	var assets := definition.get("editable_assets", []) as Array
	_check(not assets.is_empty(), "%s/%s inventories portable models" % [biome_id, role])
	for asset_v in assets:
		_check_portable_model(str(asset_v), "%s/%s" % [biome_id, role], false)
	var scene_path := str(definition.get("scene", ""))
	_check(FileAccess.file_exists(scene_path), "%s runtime wrapper exists" % role)
	if not FileAccess.file_exists(scene_path):
		return
	var scene_text := FileAccess.get_file_as_string(scene_path)
	_check(scene_text.contains("metadata/editable_asset_root"),
		"%s runtime wrapper names its portable asset root" % role)
	_check(scene_text.contains("ext_resource type=\"Mesh\""),
		"%s wrapper contains imported model geometry" % role)
	_check(not scene_text.contains("sub_resource type=\"BoxMesh\"") \
		and not scene_text.contains("sub_resource type=\"CylinderMesh\"") \
		and not scene_text.contains("sub_resource type=\"SphereMesh\"") \
		and not scene_text.contains("sub_resource type=\"TorusMesh\""),
		"%s visible geometry is external, not a scene primitive" % role)


func _check_portable_model(
	model_path: String,
	label: String,
	import_mesh := true,
	require_manifest := false
) -> void:
	var stem := model_path.trim_suffix(".obj")
	_check(FileAccess.file_exists(model_path), "%s OBJ exists" % label)
	_check(FileAccess.file_exists(stem + ".mtl"), "%s MTL exists" % label)
	_check(FileAccess.file_exists(stem + ".png"), "%s external texture exists" % label)
	if require_manifest:
		var manifest_path := stem + ".asset.json"
		_check(FileAccess.file_exists(manifest_path), "%s has a deterministic bake manifest" % label)
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) \
			if FileAccess.file_exists(manifest_path) else {}
		_check(str(manifest.get("asset_contract", "")) == "editable_3d_v1" \
			and int(manifest.get("uv_islands", 0)) > 0,
			"%s manifest records a UV-mapped editable bake" % label)
		return
	if not import_mesh:
		var obj_text := FileAccess.get_file_as_string(model_path)
		_check(obj_text.contains("\nvt ") or obj_text.begins_with("vt "),
			"%s OBJ contains editable UV coordinates" % label)
		_check(obj_text.contains("mtllib "), "%s OBJ binds its external MTL" % label)
		return
	var mesh := load(model_path) as ArrayMesh
	_check(mesh != null and mesh.get_surface_count() > 0, "%s OBJ imports as mesh" % label)
	if mesh == null or mesh.get_surface_count() == 0:
		return
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
		_check(not uvs.is_empty(), "%s surface %d has editable UVs" % [label, surface])
func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		failures += 1
		push_error("  FAIL: %s" % message)
