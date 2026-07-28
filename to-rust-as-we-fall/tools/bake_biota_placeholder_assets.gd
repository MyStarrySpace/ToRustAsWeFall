extends SceneTree

## Deterministically bakes the tooling-only biota construction recipe into portable,
## Blockbench-ready OBJ/MTL/PNG families. The runtime catalog references only those exports.
##
## Run from the project directory:
##   ..\Godot_v4.7-stable_win64_console.exe --headless --path . \
##     --script res://tools/bake_biota_placeholder_assets.gd
##
## Set BIOTA_ASSET to seefern, hushbloom, scarpet, or sapscrap to rebake one silhouette.

const SOURCE_SCENE := "res://tools/asset_sources/biota_placeholder_kit_source.tscn"
const OUTPUT_ROOT := "res://resources/models/shared/biota_placeholders"

const EXPORTS := [
	{
		"asset": "seefern",
		"file": "seefern_body",
		"names": [
			"SeefernStem",
			"SeefernFrondLeftOuter",
			"SeefernFrondLeftInner",
			"SeefernFrondCenter",
			"SeefernFrondRightInner",
			"SeefernFrondRightOuter",
			"SeefernRearFrond",
		],
		"base_color": Color(0.09, 0.31, 0.21),
		"grime_color": Color(0.025, 0.105, 0.075),
		"wear_color": Color(0.27, 0.57, 0.4),
		"px_per_m": 48,
	},
	{
		"asset": "seefern",
		"file": "seefern_signal",
		"names": ["SeefernSignalLeft", "SeefernSignalCenter", "SeefernSignalRight"],
		"base_color": Color(0.2, 0.63, 0.7),
		"grime_color": Color(0.035, 0.18, 0.22),
		"wear_color": Color(0.57, 0.95, 1.0),
		"px_per_m": 64,
	},
	{
		"asset": "hushbloom",
		"file": "hushbloom_body",
		"names": [
			"HushbloomStem",
			"HushbloomLeafLeft",
			"HushbloomLeafRight",
			"HushbloomLeafRear",
		],
		"base_color": Color(0.17, 0.28, 0.16),
		"grime_color": Color(0.055, 0.095, 0.05),
		"wear_color": Color(0.39, 0.53, 0.31),
		"px_per_m": 48,
	},
	{
		"asset": "hushbloom",
		"file": "hushbloom_signal",
		"names": [
			"HushbloomPetalNorth",
			"HushbloomPetalSouth",
			"HushbloomPetalWest",
			"HushbloomPetalEast",
			"HushbloomPetalDiagonalA",
			"HushbloomPetalDiagonalB",
			"HushbloomChargedCore",
		],
		"base_color": Color(0.68, 0.28, 0.43),
		"grime_color": Color(0.22, 0.055, 0.105),
		"wear_color": Color(1.0, 0.65, 0.76),
		"px_per_m": 64,
	},
	{
		"asset": "scarpet",
		"file": "scarpet",
		"names": [
			"ScarpetRunnerNorthSouth",
			"ScarpetRunnerEastWest",
			"ScarpetRunnerDiagonalA",
			"ScarpetRunnerDiagonalB",
			"ScarpetNodeNorth",
			"ScarpetNodeEast",
			"ScarpetNodeSouth",
			"ScarpetNodeWest",
			"ScarpetLeafTuft",
		],
		"base_color": Color(0.3, 0.43, 0.17),
		"grime_color": Color(0.08, 0.12, 0.035),
		"wear_color": Color(0.64, 0.72, 0.29),
		"px_per_m": 48,
	},
	{
		"asset": "sapscrap",
		"file": "sapscrap_body",
		"names": [
			"SapscrapCore",
			"SapscrapCarapace",
			"SapscrapPalpAInner",
			"SapscrapPalpAOuter",
			"SapscrapPalpAClawLeft",
			"SapscrapPalpAClawRight",
			"SapscrapPalpBInner",
			"SapscrapPalpBOuter",
			"SapscrapPalpBClawLeft",
			"SapscrapPalpBClawRight",
			"SapscrapPalpCInner",
			"SapscrapPalpCOuter",
			"SapscrapPalpCClawLeft",
			"SapscrapPalpCClawRight",
		],
		"base_color": Color(0.39, 0.28, 0.2),
		"grime_color": Color(0.13, 0.075, 0.05),
		"wear_color": Color(0.65, 0.49, 0.31),
		"px_per_m": 48,
	},
	{
		"asset": "sapscrap",
		"file": "sapscrap_signal",
		"names": ["SapscrapActivePalpSignal"],
		"base_color": Color(0.91, 0.54, 0.18),
		"grime_color": Color(0.31, 0.12, 0.025),
		"wear_color": Color(1.0, 0.84, 0.42),
		"px_per_m": 64,
	},
]


func _init() -> void:
	var baker = load("res://scripts/generation/uv_atlas_baker.gd")
	var packed := load(SOURCE_SCENE) as PackedScene
	if packed == null:
		push_error("[BIOTA ASSET BAKE] Could not load %s" % SOURCE_SCENE)
		quit(1)
		return
	var source_root := packed.instantiate() as Node3D
	if source_root == null:
		push_error("[BIOTA ASSET BAKE] Source scene has no Node3D root")
		quit(1)
		return
	var requested := OS.get_environment("BIOTA_ASSET").strip_edges().to_lower()
	var failed := false
	var exported := 0
	for export_spec_v in EXPORTS:
		var export_spec := export_spec_v as Dictionary
		var asset := str(export_spec["asset"])
		if requested != "" and requested != asset:
			continue
		var combined := _combine_named_meshes(source_root, export_spec["names"] as Array)
		if combined == null or combined.get_surface_count() == 0:
			push_error("[BIOTA ASSET BAKE] No geometry selected for %s" % str(export_spec["file"]))
			failed = true
			continue
		var baked: Dictionary = baker.bake(combined, {
			"base_color": export_spec["base_color"],
			"grime_color": export_spec["grime_color"],
			"wear_color": export_spec["wear_color"],
			"px_per_m": int(export_spec["px_per_m"]),
		})
		if baked.is_empty():
			push_error("[BIOTA ASSET BAKE] UV bake failed for %s" % str(export_spec["file"]))
			failed = true
			continue
		var output_dir := OUTPUT_ROOT.path_join(asset)
		var absolute_dir := ProjectSettings.globalize_path(output_dir)
		if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
			push_error("[BIOTA ASSET BAKE] Could not create %s" % absolute_dir)
			failed = true
			continue
		var path_base := absolute_dir.path_join(str(export_spec["file"]))
		if not baker.export_obj(baked, path_base):
			push_error("[BIOTA ASSET BAKE] Export failed for %s" % path_base)
			failed = true
			continue
		exported += 1
		print("[BIOTA ASSET BAKE] %s.obj (islands=%d, atlas=%dx%d)" % [
			path_base,
			int(baked["islands"]),
			(baked["image"] as Image).get_width(),
			(baked["image"] as Image).get_height(),
		])
	source_root.free()
	if requested != "" and exported == 0:
		push_error("[BIOTA ASSET BAKE] Unknown BIOTA_ASSET '%s'" % requested)
		failed = true
	quit(1 if failed else 0)


func _combine_named_meshes(root: Node3D, names: Array) -> ArrayMesh:
	var selected := {}
	for name_v in names:
		selected[str(name_v)] = true
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_selected(root, Transform3D.IDENTITY, selected, surface_tool, true)
	return surface_tool.commit()


func _append_selected(
		node: Node,
		parent_transform: Transform3D,
		selected: Dictionary,
		surface_tool: SurfaceTool,
		is_root: bool = false
) -> void:
	var current_transform := parent_transform
	if node is Node3D and not is_root:
		current_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and selected.has(node.name):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in range(mesh.get_surface_count()):
				surface_tool.append_from(mesh, surface, current_transform)
	for child in node.get_children():
		_append_selected(child, current_transform, selected, surface_tool)
