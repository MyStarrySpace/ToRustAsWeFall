extends SceneTree

## Bake canonical or seeded architecture-generator specimens into complete Blockbench kits.
## Unlike the old base-only bake, this gathers the final body, entrances, lattice, ledges,
## pipes, and district-specific detail passes from the same showcase builder used in game.
##
## Env:
##   BUILDING = canonical kind or "all" (default: all)
##   SEED     = deterministic generator seed (default: 0)
##   OUT_DIR  = output root (default: resources/models/generated-architecture)
##
##   ..\Godot_v4.7-stable_win64_console.exe --headless --path . \
##     --script res://tools/bake_building_kit.gd

const SHOWCASE_SCENE := "res://scenes/fragments/chunks/architecture_showcase.tscn"
const DEFAULT_OUTPUT := "res://resources/models/generated-architecture"
const EXCLUDED_VISUAL_NODES := ["Anchor", "VoronoiFar"]


func _init() -> void:
	var builder = load("res://scripts/generation/base_shape_builder.gd")
	var baker = load("res://scripts/generation/uv_atlas_baker.gd")
	var requested := OS.get_environment("BUILDING").strip_edges()
	if requested == "":
		requested = "all"
	var seed_value := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 0
	var output_root := OS.get_environment("OUT_DIR").strip_edges()
	if output_root == "":
		output_root = DEFAULT_OUTPUT
	var kinds: Array = builder.BUILDINGS.duplicate() if requested == "all" else [requested]
	for kind_v in kinds:
		if not builder.BUILDINGS.has(str(kind_v)):
			push_error("[BUILDING CATALOG] Unknown building '%s'" % str(kind_v))
			quit(1)
			return

	var packed := load(SHOWCASE_SCENE) as PackedScene
	if packed == null:
		push_error("[BUILDING CATALOG] Cannot load %s" % SHOWCASE_SCENE)
		quit(1)
		return
	var showcase := packed.instantiate()
	showcase.call("configure_chunk", {"seed": seed_value})
	get_root().add_child(showcase)
	for frame in range(3):
		await process_frame
	showcase.set_process(false)

	var failed := false
	for kind_v in kinds:
		var kind := str(kind_v)
		var hero := showcase.find_child("Hero_%s" % kind, true, false) as Node3D
		if hero == null:
			push_error("[BUILDING CATALOG] Showcase did not build %s" % kind)
			failed = true
			continue
		var mesh := _combine_visible_geometry(hero)
		if mesh == null or mesh.get_surface_count() == 0:
			push_error("[BUILDING CATALOG] %s has no exportable geometry" % kind)
			failed = true
			continue
		var spec: Dictionary = builder.generate(kind, seed_value)
		var base_color: Color = spec.get("color", Color(0.35, 0.38, 0.38))
		var baked: Dictionary = baker.bake(mesh, {
			"base_color": base_color,
			"grime_color": base_color.darkened(0.62),
			"wear_color": base_color.lightened(0.34),
			"px_per_m": 20,
		})
		if baked.is_empty():
			failed = true
			continue
		var folder := output_root.path_join(kind)
		var absolute_folder := ProjectSettings.globalize_path(folder)
		if DirAccess.make_dir_recursive_absolute(absolute_folder) != OK:
			push_error("[BUILDING CATALOG] Cannot create %s" % absolute_folder)
			failed = true
			continue
		var basename := "%s_seed_%d" % [kind, seed_value]
		var output_base := absolute_folder.path_join(basename)
		if not baker.export_obj(baked, output_base):
			failed = true
			continue
		var manifest := FileAccess.open(output_base + ".asset.json", FileAccess.WRITE)
		if manifest == null:
			push_error("[BUILDING CATALOG] Cannot write manifest for %s" % output_base)
			failed = true
			continue
		manifest.store_string(JSON.stringify({
			"asset_contract": "editable_3d_v1",
			"kind": kind,
			"seed": seed_value,
			"source_scene": SHOWCASE_SCENE,
			"uv_islands": int(baked["islands"]),
			"atlas_size": [(baked["image"] as Image).get_width(), (baked["image"] as Image).get_height()],
		}, "\t"))
		print("[BUILDING CATALOG] %s.obj (seed=%d, islands=%d, atlas=%dx%d)" % [
			output_base, seed_value, int(baked["islands"]),
			(baked["image"] as Image).get_width(), (baked["image"] as Image).get_height(),
		])
	showcase.queue_free()
	await process_frame
	quit(1 if failed else 0)


func _combine_visible_geometry(root: Node3D) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_inverse := root.global_transform.affine_inverse()
	var appended := false
	for raw_node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := raw_node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null or EXCLUDED_VISUAL_NODES.has(str(mesh_node.name)):
			continue
		var local_transform := root_inverse * mesh_node.global_transform
		for surface in range(mesh_node.mesh.get_surface_count()):
			tool.append_from(mesh_node.mesh, surface, local_transform)
			appended = true
	return tool.commit() if appended else null
