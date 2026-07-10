extends SceneTree

## Bake a generated building into a Blockbench hand-painting kit (.obj + .mtl + template .png with
## pixel-art edge wear). Env: BUILDING = spec kind (default open_files), OUT_DIR = output directory.
##   ../Godot_v4.7-stable_win64_console.exe --headless --path "." --script tools/bake_building_kit.gd

func _init() -> void:
	var kind := OS.get_environment("BUILDING")
	if kind == "":
		kind = "open_files"
	var out_dir := OS.get_environment("OUT_DIR")
	if out_dir == "":
		out_dir = OS.get_user_data_dir()
	var builder = load("res://scripts/generation/base_shape_builder.gd")
	var lattice = load("res://scripts/generation/lattice_builder.gd")
	var baker = load("res://scripts/generation/uv_atlas_baker.gd")
	var spec: Dictionary = builder.generate(kind)
	var ent: Dictionary = lattice.entrances(spec)
	var reserved: Array = ent.get("reserved", [])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(builder.base_mesh(spec, reserved), 0, Transform3D.IDENTITY)
	if str(spec.get("lattice", "")) == "rackwork":
		st.append_from((builder.rack_mesh(spec, reserved) as Dictionary)["frame"] as ArrayMesh, 0, Transform3D.IDENTITY)
	var baked: Dictionary = baker.bake(st.commit(), {"base_color": spec.get("color", Color(0.35, 0.38, 0.38))})
	if baked.is_empty():
		print("[BAKE] FAILED for %s" % kind)
		quit(1)
		return
	var base := out_dir.path_join("%s_kit" % kind)
	var ok: bool = baker.export_obj(baked, base)
	print("[BAKE] %s -> %s.obj/.mtl/.png  (islands=%d, crease edges=%d, atlas=%dx%d)" % [
		kind, base, int(baked["islands"]), int(baked["creases"]),
		(baked["image"] as Image).get_width(), (baked["image"] as Image).get_height()])
	quit(0 if ok else 1)
