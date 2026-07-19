extends SceneTree

## Exports the authored Cleanstreets scene geometry as UV-mapped OBJ/MTL/PNG kits.
## The generated `.tscn` files remain gameplay wrappers; these files are the portable art sources
## that can be opened and repainted in Blockbench, Blender, or any ordinary OBJ editor.
##
## Run from the project directory:
##   ..\Godot_v4.7-stable_win64_console.exe --headless --path . --script tools/bake_cleanstreets_assets.gd

const PAVILION_SCENE := "res://tools/asset_sources/cleanstreets_toll_pavilion_source.tscn"
const LANE_SCENE := "res://tools/asset_sources/cleanstreets_spike_lane_source.tscn"
const OUTPUT_ROOT := "res://resources/models/cleanstreets"

const EXPORTS := [
	{
		"scene": PAVILION_SCENE,
		"folder": "toll_pavilion",
		"file": "cleanstreets_toll_pavilion_structure",
		"names": ["Dais", "FrontStep", "PierNW", "PierN", "PierNE", "PierSW", "PierS", "PierSE", "Canopy"],
		"base_color": Color(0.58, 0.51, 0.39),
		"grime_color": Color(0.25, 0.22, 0.17),
		"wear_color": Color(0.76, 0.7, 0.57),
	},
	{
		"scene": PAVILION_SCENE,
		"folder": "toll_pavilion",
		"file": "cleanstreets_toll_pavilion_fixtures",
		"names": ["DistrictFascia", "QueueFinLeft", "QueueFinMidLeft", "QueueFinMidRight", "QueueFinRight", "NoRestBenchLeft", "NoRestBenchRight", "TollKiosk"],
		"base_color": Color(0.07, 0.29, 0.28),
		"grime_color": Color(0.025, 0.12, 0.12),
		"wear_color": Color(0.24, 0.51, 0.48),
	},
	{
		"scene": PAVILION_SCENE,
		"folder": "toll_pavilion",
		"file": "cleanstreets_toll_pavilion_screen",
		"names": ["TollScreen"],
		"base_color": Color(0.08, 0.42, 0.46),
		"grime_color": Color(0.025, 0.15, 0.17),
		"wear_color": Color(0.28, 0.78, 0.81),
	},
	{
		"scene": PAVILION_SCENE,
		"folder": "toll_pavilion",
		"file": "cleanstreets_toll_pavilion_studs",
		"names": ["StudLeft", "StudMidLeft", "StudMid", "StudMidRight", "StudRight"],
		"base_color": Color(0.73, 0.72, 0.66),
		"grime_color": Color(0.28, 0.28, 0.26),
		"wear_color": Color(0.92, 0.91, 0.84),
	},
	{
		"scene": LANE_SCENE,
		"folder": "spike_lane",
		"file": "cleanstreets_spike_lane_road",
		"names": ["RoadInset"],
		"base_color": Color(0.42, 0.45, 0.47),
		"grime_color": Color(0.2, 0.22, 0.23),
		"wear_color": Color(0.66, 0.69, 0.7),
	},
	{
		"scene": LANE_SCENE,
		"folder": "spike_lane",
		"file": "cleanstreets_spike_lane_curbs",
		"names": ["NoRestCurbLeft", "NoRestCurbRight"],
		"base_color": Color(0.09, 0.28, 0.27),
		"grime_color": Color(0.025, 0.11, 0.11),
		"wear_color": Color(0.27, 0.49, 0.46),
	},
	{
		"scene": LANE_SCENE,
		"folder": "spike_lane",
		"file": "cleanstreets_spike_lane_studs",
		"names": ["StudNW", "StudN", "StudNE", "StudW", "StudC", "StudE", "StudSW", "StudS", "StudSE"],
		"base_color": Color(0.76, 0.73, 0.61),
		"grime_color": Color(0.3, 0.29, 0.25),
		"wear_color": Color(0.95, 0.92, 0.78),
	},
]


func _init() -> void:
	var baker = load("res://scripts/generation/uv_atlas_baker.gd")
	var instances := {}
	var failed := false
	for export_spec_v in EXPORTS:
		var export_spec := export_spec_v as Dictionary
		var scene_path := str(export_spec["scene"])
		if not instances.has(scene_path):
			var packed := load(scene_path) as PackedScene
			if packed == null:
				push_error("[CLEANSTREETS ASSET BAKE] Could not load %s" % scene_path)
				failed = true
				continue
			instances[scene_path] = packed.instantiate()
		var source_root := instances.get(scene_path) as Node3D
		if source_root == null:
			failed = true
			continue
		var combined := _combine_named_meshes(source_root, export_spec["names"] as Array)
		if combined == null or combined.get_surface_count() == 0:
			push_error("[CLEANSTREETS ASSET BAKE] No geometry selected for %s" % str(export_spec["file"]))
			failed = true
			continue
		var baked: Dictionary = baker.bake(combined, {
			"base_color": export_spec["base_color"],
			"grime_color": export_spec["grime_color"],
			"wear_color": export_spec["wear_color"],
		})
		if baked.is_empty():
			push_error("[CLEANSTREETS ASSET BAKE] UV bake failed for %s" % str(export_spec["file"]))
			failed = true
			continue
		var output_dir := OUTPUT_ROOT.path_join(str(export_spec["folder"]))
		var absolute_dir := ProjectSettings.globalize_path(output_dir)
		if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
			push_error("[CLEANSTREETS ASSET BAKE] Could not create %s" % absolute_dir)
			failed = true
			continue
		var path_base := absolute_dir.path_join(str(export_spec["file"]))
		if not baker.export_obj(baked, path_base):
			push_error("[CLEANSTREETS ASSET BAKE] Export failed for %s" % path_base)
			failed = true
			continue
		print("[CLEANSTREETS ASSET BAKE] %s.obj (islands=%d, atlas=%dx%d)" % [
			path_base,
			int(baked["islands"]),
			(baked["image"] as Image).get_width(),
			(baked["image"] as Image).get_height(),
		])
	for instance_v in instances.values():
		(instance_v as Node).free()
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
