extends SceneTree

## Focused art-contract guard for the intentionally replaceable world-biota kit. Gameplay/save
## behavior belongs to each owning flora or enemy class and is deliberately outside this verifier.

const Catalog := preload("res://scripts/game/objects/biota_placeholder_catalog.gd")
const SOURCE_SCENE := "res://tools/asset_sources/biota_placeholder_kit_source.tscn"
const BAKE_TOOL := "res://tools/bake_biota_placeholder_assets.gd"
const CATALOG_SCENE := "res://scenes/props/biota/placeholder_biota_catalog.tscn"

const ASSETS := [
	{
		"key": "flora/seefern",
		"scene": "res://scenes/props/biota/placeholder_seefern.tscn",
		"stems": [
			"res://resources/models/shared/biota_placeholders/seefern/seefern_body",
			"res://resources/models/shared/biota_placeholders/seefern/seefern_signal",
		],
		"minimum_size": Vector3(1.0, 1.15, 0.25),
		"maximum_size": Vector3(1.8, 1.8, 1.2),
	},
	{
		"key": "flora/hushbloom",
		"scene": "res://scenes/props/biota/placeholder_hushbloom.tscn",
		"stems": [
			"res://resources/models/shared/biota_placeholders/hushbloom/hushbloom_body",
			"res://resources/models/shared/biota_placeholders/hushbloom/hushbloom_signal",
		],
		"minimum_size": Vector3(0.6, 0.65, 0.4),
		"maximum_size": Vector3(1.25, 1.2, 1.1),
	},
	{
		"key": "flora/scarpet",
		"scene": "res://scenes/props/biota/placeholder_scarpet.tscn",
		"stems": [
			"res://resources/models/shared/biota_placeholders/scarpet/scarpet",
		],
		"minimum_size": Vector3(0.9, 0.12, 0.9),
		"maximum_size": Vector3(1.6, 0.6, 1.6),
	},
	{
		"key": "fauna/sapscrap",
		"scene": "res://scenes/props/biota/placeholder_sapscrap.tscn",
		"stems": [
			"res://resources/models/shared/biota_placeholders/sapscrap/sapscrap_body",
			"res://resources/models/shared/biota_placeholders/sapscrap/sapscrap_signal",
		],
		"minimum_size": Vector3(1.35, 0.45, 1.35),
		"maximum_size": Vector3(2.3, 1.2, 2.3),
	},
]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_repeatable_source()
	_verify_catalog_contract()
	for spec_v in ASSETS:
		_verify_asset(spec_v as Dictionary)
	_verify_catalog_scene()
	print("BIOTA PLACEHOLDER ASSETS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_repeatable_source() -> void:
	var source_text := FileAccess.get_file_as_string(SOURCE_SCENE)
	var bake_text := FileAccess.get_file_as_string(BAKE_TOOL)
	_check(FileAccess.file_exists(SOURCE_SCENE)
		and source_text.contains("metadata/tooling_only = true")
		and source_text.contains("metadata/asset_contract = \"editable_3d_v1\""),
		"construction recipe is retained as tooling-only editable source")
	_check(FileAccess.file_exists(BAKE_TOOL)
		and bake_text.contains("scripts/generation/uv_atlas_baker.gd")
		and bake_text.contains("BIOTA_ASSET")
		and bake_text.contains("baker.export_obj"),
		"deterministic bake supports full-kit and one-silhouette export")
	for asset in ["seefern", "hushbloom", "scarpet", "sapscrap"]:
		_check(bake_text.contains("\"asset\": \"%s\"" % asset),
			"repeatable bake declares %s" % asset)
	_check(source_text.contains("SapscrapPalpA")
		and source_text.contains("SapscrapPalpB")
		and source_text.contains("SapscrapPalpC")
		and source_text.contains("SapscrapActivePalpSignal"),
		"Sapscrap recipe preserves the canon C3 body plan and one active-palp tell")


func _verify_catalog_contract() -> void:
	var keys := Catalog.keys()
	_check(str(Catalog.CONTRACT_ID) == "biota_placeholder_catalog_v1",
		"catalog exposes a stable versioned discovery contract")
	_check(keys.size() == ASSETS.size(),
		"catalog contains exactly the bounded starter kit")
	var flora_count := 0
	var fauna_count := 0
	for key in keys:
		var entry := Catalog.record(key)
		if str(entry.get("category", "")) == "flora":
			flora_count += 1
		elif str(entry.get("category", "")) == "fauna":
			fauna_count += 1
		_check(str(entry.get("visual_identity", "")).begins_with("placeholder_"),
			"%s is explicitly marked as a replaceable visual identity" % key)
	_check(flora_count >= 3 and fauna_count >= 1,
		"starter kit offers multiple flora silhouettes and at least one fauna silhouette")
	_check(Catalog.record("FLORA/SEEFERN") == Catalog.record("flora/seefern")
		and Catalog.record("unknown").is_empty(),
		"catalog lookup is normalized and rejects invented fallback organisms")


func _verify_asset(spec: Dictionary) -> void:
	var key := str(spec["key"])
	var entry := Catalog.record(key)
	var scene_path := str(spec["scene"])
	_check(str(entry.get("scene", "")) == scene_path,
		"%s catalog record resolves its thin wrapper" % key)
	for stem_v in spec["stems"] as Array:
		_verify_portable_family(str(stem_v), key)

	var scene_text := FileAccess.get_file_as_string(scene_path)
	_check(FileAccess.file_exists(scene_path)
		and scene_text.contains("ext_resource type=\"Mesh\"")
		and scene_text.contains("ext_resource type=\"Texture2D\""),
		"%s wrapper binds external meshes and textures" % key)
	_check(not scene_text.contains("sub_resource type=\"BoxMesh\"")
		and not scene_text.contains("sub_resource type=\"CylinderMesh\"")
		and not scene_text.contains("sub_resource type=\"SphereMesh\"")
		and not scene_text.contains("sub_resource type=\"CapsuleMesh\""),
		"%s wrapper contains no unique visible primitive geometry" % key)
	var packed := load(scene_path) as PackedScene
	var instance := packed.instantiate() as Node3D if packed != null else null
	_check(instance != null
		and str(instance.get_meta("asset_contract", "")) == "editable_3d_v1"
		and str(instance.get_meta("visual_identity", "")) \
			== str(entry.get("visual_identity", "")),
		"%s wrapper exposes its portable identity" % key)
	if instance == null:
		return
	var bounds := _mesh_bounds(instance)
	var minimum: Vector3 = spec["minimum_size"]
	var maximum: Vector3 = spec["maximum_size"]
	_check(bounds.size.x >= minimum.x
		and bounds.size.y >= minimum.y
		and bounds.size.z >= minimum.z,
		"%s silhouette is readable at world scale (%s)" % [key, bounds.size])
	_check(bounds.size.x <= maximum.x
		and bounds.size.y <= maximum.y
		and bounds.size.z <= maximum.z,
		"%s placeholder remains within its bounded placement footprint (%s)" % [key, bounds.size])
	_check(bounds.position.y >= -0.08 and bounds.position.y <= 0.18,
		"%s origin remains a ground-placement pivot (min y %.3f)" % [key, bounds.position.y])
	instance.free()


func _verify_portable_family(stem: String, owner_key: String) -> void:
	for extension in [".obj", ".mtl", ".png"]:
		_check(FileAccess.file_exists(stem + extension),
			"%s ships external %s for %s" % [
				stem.get_file(), extension.trim_prefix(".").to_upper(), owner_key])
	var obj_text := FileAccess.get_file_as_string(stem + ".obj")
	var mtl_text := FileAccess.get_file_as_string(stem + ".mtl")
	_check(obj_text.contains("mtllib %s.mtl" % stem.get_file())
		and obj_text.contains("\nvt ")
		and obj_text.contains("/"),
		"%s OBJ binds its material and UVs every face" % stem.get_file())
	_check(mtl_text.contains("map_Kd %s.png" % stem.get_file()),
		"%s MTL keeps its paint texture external" % stem.get_file())
	var texture := load(stem + ".png") as Texture2D
	var image := texture.get_image() if texture != null else null
	_check(image != null and not image.is_empty(),
		"%s paint sheet loads independently" % stem.get_file())
	var mesh := load(stem + ".obj") as ArrayMesh
	var uv_complete := mesh != null and mesh.get_surface_count() > 0
	if mesh != null:
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			uv_complete = uv_complete \
				and not (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty()
	_check(uv_complete, "%s imports independently with UVs on every surface" % stem.get_file())


func _verify_catalog_scene() -> void:
	var packed := load(CATALOG_SCENE) as PackedScene
	var instance := packed.instantiate() as Node3D if packed != null else null
	_check(instance != null
		and str(instance.get_meta("catalog_contract", "")) == Catalog.CONTRACT_ID,
		"editor-openable catalog scene advertises the same discovery contract")
	if instance == null:
		return
	for spec_v in ASSETS:
		var key := str((spec_v as Dictionary)["key"])
		var identity := str(Catalog.record(key).get("visual_identity", ""))
		_check(instance.find_child(identity, true, false) != null,
			"catalog scene displays %s" % key)
	instance.free()


func _mesh_bounds(root: Node3D) -> AABB:
	var aggregate := {"bounds": AABB(), "has_bounds": false}
	_merge_mesh_bounds(root, Transform3D.IDENTITY, aggregate, true)
	return aggregate["bounds"] as AABB


func _merge_mesh_bounds(
		node: Node,
		parent_transform: Transform3D,
		aggregate: Dictionary,
		is_root: bool = false
) -> void:
	var current_transform := parent_transform
	if node is Node3D and not is_root:
		current_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var transformed := current_transform * mesh_instance.mesh.get_aabb()
			aggregate["bounds"] = transformed if not bool(aggregate["has_bounds"]) \
				else (aggregate["bounds"] as AABB).merge(transformed)
			aggregate["has_bounds"] = true
	for child in node.get_children():
		_merge_mesh_bounds(child, current_transform, aggregate)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		push_error("  FAIL: %s" % message)
