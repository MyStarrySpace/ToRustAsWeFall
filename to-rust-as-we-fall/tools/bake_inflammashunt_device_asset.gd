extends SceneTree

## Deterministically bakes the tooling-only catalyst construction scene into a portable,
## UV-mapped OBJ/MTL/PNG kit. Runtime code loads only the resulting wrapper scene.

const SOURCE := "res://tools/asset_sources/inflammashunt_device_source.tscn"
const OUTPUT_DIR := "res://resources/models/inflammashunt/resolution_catalyst"
const OUTPUT_FILE := "resolution_catalyst"
const PARTS := [
	"CatalystCore", "CatalystFlowRing", "CatalystCap",
	"CatalystFinEast", "CatalystFinWest", "CatalystFinNorth", "CatalystFinSouth",
	"CatalystDatumEast", "CatalystDatumWest",
]


func _init() -> void:
	var packed := load(SOURCE) as PackedScene
	if packed == null:
		push_error("[INFLAMMASHUNT ASSET] Cannot load %s" % SOURCE)
		quit(1)
		return
	var source := packed.instantiate() as Node3D
	var mesh := _combine_named_meshes(source, PARTS)
	var baker = load("res://scripts/generation/uv_atlas_baker.gd")
	var baked: Dictionary = baker.bake(mesh, {
		"base_color": Color(0.16, 0.34, 0.28),
		"grime_color": Color(0.035, 0.085, 0.065),
		"wear_color": Color(0.52, 0.92, 0.70),
		"px_per_m": 96,
	})
	if baked.is_empty():
		push_error("[INFLAMMASHUNT ASSET] UV bake failed")
		source.free()
		quit(1)
		return
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		push_error("[INFLAMMASHUNT ASSET] Cannot create %s" % absolute_dir)
		source.free()
		quit(1)
		return
	var path_base := absolute_dir.path_join(OUTPUT_FILE)
	var ok: bool = baker.export_obj(baked, path_base)
	if ok:
		print("[INFLAMMASHUNT ASSET] %s.obj (islands=%d, atlas=%dx%d)" % [
			path_base, int(baked["islands"]),
			(baked["image"] as Image).get_width(), (baked["image"] as Image).get_height(),
		])
	source.free()
	quit(0 if ok else 1)


func _combine_named_meshes(root: Node3D, names: Array) -> ArrayMesh:
	var selected := {}
	for value in names:
		selected[str(value)] = true
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_selected(root, Transform3D.IDENTITY, selected, tool, true)
	return tool.commit()


func _append_selected(
		node: Node,
		parent_transform: Transform3D,
		selected: Dictionary,
		tool: SurfaceTool,
		is_root := false
	) -> void:
	var current := parent_transform
	if node is Node3D and not is_root:
		current = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and selected.has(node.name):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in range(mesh.get_surface_count()):
				tool.append_from(mesh, surface, current)
	for child in node.get_children():
		_append_selected(child, current, selected, tool)

