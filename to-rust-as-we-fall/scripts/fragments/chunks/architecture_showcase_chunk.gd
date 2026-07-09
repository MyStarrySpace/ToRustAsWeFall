extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

## ARCHITECTURE SHOWCASE — a walkable gallery of the district buildings, built BOTTOM-UP, one step at
## a time. STEP 1 (now): each building is its LOW-POLY BASE SHAPE (BaseShapeBuilder), matching the
## reference plate's overall massing — the Plumbing Power Project is a squat cylinder, the Honeycomb
## Cooperative is a tall box. Detail (lobes, domes, honeycomb facades, signage) gets layered on in
## later steps; this is the iteration surface — walk the row and check the proportions against the
## reference plates. Cosmetic turntables. (N reseeds generation previews, but base shapes are fixed
## for now — nothing to reroll until we add varied detail.)

const BaseShape := preload("res://scripts/generation/base_shape_builder.gd")
const Lattice := preload("res://scripts/generation/lattice_builder.gd")

const SPACING := 7.0
const GROUND_TILE := "facility_metal"

var _seed := 1
var _turntables: Array = []
var _specimens: Array = []

func configure_chunk(config: Dictionary) -> void:
	if config.has("seed"):
		_seed = int(config["seed"])

func is_generation_preview() -> bool:
	return true

func get_generation_seed() -> int:
	return _seed

func get_scene_title() -> String:
	return "Architecture Showcase — base shapes"

func _build_chunk() -> void:
	fragment = _gallery_fragment()
	super._build_chunk()
	_turntables.clear()
	_specimens.clear()
	var kinds: Array = BaseShape.BUILDINGS
	for i in range(kinds.size()):
		var kind := str(kinds[i])
		var spec: Dictionary = BaseShape.generate(kind)
		var root := Node3D.new()
		root.name = "Hero_%s" % kind
		root.position = _plinth_pos(i, kinds.size()) + Vector3(0, 0.55, 0)
		add_child(root)
		var body := BaseShape.base_mesh(spec)
		var verts := 0
		if body != null:
			body.surface_set_material(0, _tinted_tile_material(str(spec.get("tile", "facility_metal")), spec.get("color", Color(0.4, 0.4, 0.42))))
			var mi := MeshInstance3D.new()
			mi.name = "Body"
			mi.mesh = body
			root.add_child(mi)
			verts = body.surface_get_array_len(0)
		_add_lattice(root, spec)
		_add_entrances(root, spec)
		_specimens.append({"building": kind, "shape": str(spec.get("shape", "")),
			"lattice": str(spec.get("lattice", "")), "verts": verts})
		_turntables.append(root)

## STEP 3: entrances (main + side/enforcement doors) + a readable nameplate sign over the main door.
func _add_entrances(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = Lattice.entrances(spec)
	_add_lattice_mesh(root, "EntStone", built.get("stone"), _tinted_tile_material("facility_metal", Color(0.66, 0.62, 0.50)))
	var darkmat := StandardMaterial3D.new()
	darkmat.albedo_color = Color(0.05, 0.05, 0.06)
	darkmat.roughness = 0.92
	_add_lattice_mesh(root, "EntDark", built.get("dark"), darkmat)
	var teal := StandardMaterial3D.new()
	teal.albedo_color = Color(0.10, 0.28, 0.30)
	teal.emission_enabled = true
	teal.emission = Color(0.22, 0.82, 0.86)   # enforcement-vestibule glow
	teal.emission_energy_multiplier = 1.7
	_add_lattice_mesh(root, "EntAccent", built.get("accent"), teal)
	# Readable nameplate over the main door (billboarded so it stays legible as the plinth turntables).
	var lbl := Label3D.new()
	lbl.name = "Nameplate"
	lbl.text = str(spec.get("title", "")).to_upper()
	lbl.font_size = 44
	lbl.pixel_size = 0.006
	lbl.modulate = Color(0.96, 0.86, 0.56)
	lbl.outline_size = 10
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.position = built.get("main_top", Vector3(0, 3, 3))
	root.add_child(lbl)

## STEP 2: layer the building's declared lattice elements onto its base shape — a facade lattice
## (honeyframe / tracery) plus optional draped pipes.
func _add_lattice(root: Node3D, spec: Dictionary) -> void:
	match str(spec.get("lattice", "")):
		"honeyframe":
			_add_honeyframe(root, spec)
		"tracery":
			_add_tracery(root, spec)
	if bool(spec.get("pipes", false)):
		_add_pipes(root, spec)

func _add_honeyframe(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = Lattice.honeyframe(spec.get("size", Vector3(4.5, 8.0, 5.5)))
	# Brighter cream than the base body so the strut lattice reads proud of the wall.
	_add_lattice_mesh(root, "HoneyFrame", built.get("frame"), _tinted_tile_material("facility_metal", Color(0.72, 0.69, 0.58)))
	_add_lattice_mesh(root, "HoneyGlass", built.get("glass"), _window_material(1.8))

func _add_tracery(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = Lattice.tracery(float(spec.get("radius", 2.4)), float(spec.get("height", 7.2)))
	_add_lattice_mesh(root, "TraceryRibs", built.get("frame"), _tinted_tile_material("facility_metal", Color(0.74, 0.70, 0.57)))
	_add_lattice_mesh(root, "TraceryGlass", built.get("glass"), _window_material(3.6))

func _add_pipes(root: Node3D, spec: Dictionary) -> void:
	var pipe_seed := int(str(spec.get("kind", "")).hash())
	var mesh := Lattice.pipes(spec, pipe_seed)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true   # the pipe carries its metal/rust patina as vertex colour
	mat.metallic = 0.5
	mat.roughness = 0.75
	_add_lattice_mesh(root, "Pipes", mesh, mat)

func _add_lattice_mesh(root: Node3D, mesh_name: String, mesh, mat: Material) -> void:
	if mesh == null or (mesh as ArrayMesh).get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	mi.material_override = mat
	root.add_child(mi)

## The window shader reads each pane's per-vertex COLOR as its own light, so one glass mesh shows a
## facade of individually lit / dim / dark windows. `energy` is the global brightness multiplier.
func _window_material(energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://resources/window_panes.gdshader")
	m.set_shader_parameter("energy", energy)
	return m

func _process(delta: float) -> void:
	for t in _turntables:
		if is_instance_valid(t):
			(t as Node3D).rotate_y(delta * 0.25)

func get_preview_state() -> Dictionary:
	var st: Dictionary = super.get_preview_state()
	st["seed"] = _seed
	st["buildings"] = _specimens.size()
	return st

func _plinth_pos(i: int, n: int) -> Vector3:
	return Vector3((float(i) - float(n - 1) * 0.5) * SPACING, 0.0, -3.0)

func _gallery_fragment() -> Fragment:
	var frag := Fragment.new()
	frag.id = "architecture_showcase_%d" % _seed
	frag.title = "Architecture Showcase — base shapes"
	frag.help = "The district buildings as their low-poly base shapes. Walk the row; compare to the reference plates."
	frag.default_character = "aster"
	frag.party_ids = PackedStringArray(["aster", "peris", "endo"])
	var cs := 1.5
	var kinds: Array = BaseShape.BUILDINGS
	var w := int(ceil(kinds.size() * SPACING / cs)) + 6
	var h := 10
	frag.floors = [{
		"pos": Vector3(0, -0.05, 0), "size": Vector3(w * cs, 0.1, h * cs),
		"color": Color(0.10, 0.11, 0.13), "tile": "deck_metal",
	}]
	var origin_x := -w * cs * 0.5
	var origin_z := -h * cs * 0.5
	var walls: Array[Dictionary] = []
	var plinth_cells := {}
	for i in range(kinds.size()):
		var p := _plinth_pos(i, kinds.size())
		walls.append({"pos": Vector3(p.x, 0.28, p.z), "size": Vector3(3.0, 0.56, 3.0),
			"color": Color(0.15, 0.16, 0.18), "tile": GROUND_TILE})
		var cxi := int((p.x - origin_x) / cs)
		var czi := int((p.z - origin_z) / cs)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				plinth_cells[Vector2i(cxi + dx, czi + dz)] = true
	frag.walls = walls
	var cells: Array = []
	for z in range(h):
		for x in range(w):
			if not plinth_cells.has(Vector2i(x, z)):
				cells.append([x, z])
	frag.grid = {
		"contract_id": "unified_grid_v1", "cell_size": cs,
		"origin": [origin_x, 0.0, origin_z], "width": w, "height": h,
		"walkable_cells": cells,
	}
	frag.spawns = {
		"aster": Vector3(-1.5, 0.5, 4.2), "peris": Vector3(0.0, 0.5, 4.2), "endo": Vector3(1.5, 0.5, 4.2),
	}
	frag.shelters = [{"min": Vector2(origin_x + cs, 2.6), "max": Vector2(-origin_x - cs, 6.5)}]
	# Gallery lighting: a key + a low fill per plinth so the forms read top-to-base, plus a broad
	# front wash. Bright — the silhouette is the point here, not mood.
	var lights: Array[Dictionary] = []
	for i in range(kinds.size()):
		var p2 := _plinth_pos(i, kinds.size())
		lights.append({"pos": p2 + Vector3(-2.5, 10.0, 4.0), "color": Color(0.85, 0.87, 0.9),
			"energy": 4.5, "range": 20.0})
		lights.append({"pos": p2 + Vector3(2.5, 2.5, 3.5), "color": Color(0.6, 0.64, 0.72),
			"energy": 2.2, "range": 12.0})
	lights.append({"pos": Vector3(0, 7.0, 8.0), "color": Color(0.62, 0.68, 0.76), "energy": 2.0, "range": 30.0})
	frag.lights = lights
	var labels: Array[Dictionary] = []
	for i in range(kinds.size()):
		var kind := str(kinds[i])
		var p3 := _plinth_pos(i, kinds.size())
		var title := str((BaseShape.SPECS[kind] as Dictionary).get("title", kind))
		labels.append({"text": title, "pos": p3 + Vector3(0, 0.9, 1.6), "color": Color(0.62, 0.68, 0.6)})
	frag.labels = labels
	frag.params = {"stamina_field_regen": true, "showcase_seed": _seed}
	frag.time_state = {"note_default": "Architecture showcase — base shapes.", "routing_mode": "safe"}
	return frag
