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
const Ledge := preload("res://scripts/generation/ledge_builder.gd")

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
		# Entrances FIRST (front + distributed sides): their reserved regions cut real OPENINGS into the
		# base mesh AND clear the lattice, so the door parts never z-fight a solid wall.
		var ent: Dictionary = Lattice.entrances(spec)
		var body := BaseShape.base_mesh(spec, ent.get("reserved", []))
		var verts := 0
		if body != null:
			body.surface_set_material(0, _tinted_tile_material(str(spec.get("tile", "facility_metal")), spec.get("color", Color(0.4, 0.4, 0.42))))
			var mi := MeshInstance3D.new()
			mi.name = "Body"
			mi.mesh = body
			root.add_child(mi)
			verts = body.surface_get_array_len(0)
		_add_lattice(root, spec, ent.get("reserved", []))
		_add_ledge_treatments(root, spec)
		_add_entrance_meshes(root, spec, ent)
		_add_anchor_markers(root, BaseShape.gameplay_anchors(spec, ent))
		_specimens.append({"building": kind, "shape": str(spec.get("shape", "")),
			"lattice": str(spec.get("lattice", "")), "verts": verts})
		_turntables.append(root)

## GAMEPLAY-ANCHOR markers (the architecture->puzzle sockets, BaseShapeBuilder.gameplay_anchors):
## small emissive gems so the sockets are inspectable in the gallery — dark red = structural WEAK
## point, green = ROAD connector, cyan = BRIDGE connector, amber = BALCONY slot.
func _add_anchor_markers(root: Node3D, anchors: Dictionary) -> void:
	var sets := [
		{"list": anchors.get("weak_points", []), "col": Color(0.85, 0.15, 0.1), "r": 0.11},
		{"list": anchors.get("connectors", []), "col": Color(0.2, 0.9, 0.4), "r": 0.09},
		{"list": anchors.get("balcony_slots", []), "col": Color(1.0, 0.75, 0.2), "r": 0.08},
	]
	for sd in sets:
		var s := sd as Dictionary
		for a in (s["list"] as Array):
			var ad := a as Dictionary
			var col := s["col"] as Color
			if str(ad.get("kind", "")) == "bridge":
				col = Color(0.2, 0.8, 0.95)
			var gem := MeshInstance3D.new()
			gem.name = "Anchor"
			var sm := SphereMesh.new()
			sm.radius = float(s["r"])
			sm.height = float(s["r"]) * 2.0
			gem.mesh = sm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = col
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = 0.8
			gem.material_override = m
			gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gem.position = ad["pos"] as Vector3
			root.add_child(gem)

## STEP 3: place the precomputed entrance meshes (main + distributed side/enforcement doors) + a
## readable nameplate over the MAIN (front) door.
func _add_entrance_meshes(root: Node3D, spec: Dictionary, built: Dictionary) -> void:
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

## STEP 2: layer the building's declared lattice onto its base shape — a facade lattice (honeyframe /
## tracery) that RESERVES space for the entrances, plus optional draped pipes.
func _add_lattice(root: Node3D, spec: Dictionary, reserved: Array) -> void:
	match str(spec.get("lattice", "")):
		"honeyframe":
			_add_honeyframe(root, spec, reserved)
		"tracery":
			_add_tracery(root, spec, reserved)
		"voronoi":
			_add_voronoi(root, spec, reserved)
		"rackwork":
			_add_rackwork(root, spec, reserved)
	if bool(spec.get("pipes", false)):
		_add_pipes(root, spec)

func _add_honeyframe(root: Node3D, spec: Dictionary, reserved: Array) -> void:
	# On a tiered "cake" the lattice runs PER vertical drum band (each at its tier's footprint); a flat
	# base is one band.
	var built: Dictionary = Lattice.honeyframe_tiered(spec, {"reserved": reserved}) if int(spec.get("tiers", 1)) > 1 \
		else Lattice.honeyframe(spec.get("size", Vector3(4.5, 8.0, 5.5)), {"reserved": reserved})
	# Brighter cream than the base body so the strut lattice reads proud of the wall.
	_add_lattice_mesh(root, "HoneyFrame", built.get("frame"), _tinted_tile_material("facility_metal", Color(0.72, 0.69, 0.58)))
	_add_lattice_mesh(root, "HoneyGlass", built.get("glass"), _window_material(1.8))

func _add_tracery(root: Node3D, spec: Dictionary, reserved: Array) -> void:
	var ov := {"reserved": reserved}
	if spec.has("bays"):
		ov["bays"] = int(spec["bays"])   # the entrances snapped to this bay grid — keep them aligned
	var built: Dictionary = Lattice.tracery_tiered(spec, ov) if int(spec.get("tiers", 1)) > 1 \
		else Lattice.tracery(float(spec.get("radius", 2.4)), float(spec.get("height", 7.2)), ov)
	_add_lattice_mesh(root, "TraceryRibs", built.get("frame"), _tinted_tile_material("facility_metal", Color(0.74, 0.70, 0.57)))
	_add_lattice_mesh(root, "TraceryGlass", built.get("glass"), _window_material(3.6))

## STEP 3: decorate the flat ledge rings of a tiered "cake" base. `ledge_treatments` on the spec picks
## railings (algorithm-4 cards) / planters / greenery; an empty list leaves the ledges FLAT (bare).
func _add_ledge_treatments(root: Node3D, spec: Dictionary) -> void:
	var built: Dictionary = Ledge.build(spec)
	if built.is_empty():
		return
	_add_lattice_mesh(root, "LedgeRails", built.get("rails"), _railing_material())
	var planter := StandardMaterial3D.new()
	planter.albedo_color = Color(0.30, 0.22, 0.17)          # terracotta / dark planter box
	planter.roughness = 0.95
	_add_lattice_mesh(root, "LedgePlanters", built.get("planters"), planter)
	var foliage := StandardMaterial3D.new()
	foliage.albedo_color = Color(0.24, 0.42, 0.20)          # canopy green
	foliage.roughness = 0.9
	_add_lattice_mesh(root, "LedgeGreenery", built.get("greenery"), foliage)

## The pixel-art railing tile (alpha-scissor) — one post + top & bottom rails, the rest transparent;
## tiled across a card it reads as evenly-spaced balusters. FILTER_NEAREST keeps it crisp.
func _railing_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _railing_texture()
	m.albedo_color = Color(0.86, 0.82, 0.70)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.85
	return m

func _railing_texture() -> ImageTexture:
	var tw := 12
	var th := 24
	var img := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var bar := Color(0.90, 0.86, 0.72, 1.0)
	for x in range(tw):
		img.set_pixel(x, 0, bar); img.set_pixel(x, 1, bar); img.set_pixel(x, 2, bar)
		img.set_pixel(x, th - 3, bar); img.set_pixel(x, th - 2, bar); img.set_pixel(x, th - 1, bar)
	for x in range(1, 4):
		for y in range(3, th - 3):
			img.set_pixel(x, y, bar)
	return ImageTexture.create_from_image(img)

## The Voronoi MEMBRANE (Bulwark Wharf): near = the watertight rib web; far = the SAME web baked to a
## texture quad per face. GeometryInstance3D visibility ranges cross them over — decoration becomes
## texture at distance with zero per-frame code.
func _add_voronoi(root: Node3D, spec: Dictionary, reserved: Array) -> void:
	var built: Dictionary = Lattice.voronoi(spec.get("size", Vector3(4.2, 5.2, 3.6)), {"reserved": reserved})
	var lod := float(built.get("lod_switch", 30.0))
	var mi := MeshInstance3D.new()
	mi.name = "VoronoiMembrane"
	mi.mesh = built["frame"]
	mi.material_override = _tinted_tile_material("facility_metal", Color(0.72, 0.70, 0.66))
	mi.visibility_range_end = lod
	mi.visibility_range_end_margin = 2.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(mi)
	for fd in (built["faces"] as Array):
		var f := fd as Dictionary
		var quad := MeshInstance3D.new()
		quad.name = "VoronoiFar"
		var qm := QuadMesh.new()
		qm.size = Vector2(float(f["w"]), float(f["h"]))
		quad.mesh = qm
		var m := StandardMaterial3D.new()
		m.albedo_texture = f["tex"]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.roughness = 0.85
		quad.material_override = m
		var n3 := f["n"] as Vector3
		var u3 := f["u"] as Vector3
		quad.transform = Transform3D(Basis(u3, Vector3.UP, n3), (f["c"] as Vector3) + n3 * 0.06)
		quad.visibility_range_begin = lod
		quad.visibility_range_begin_margin = 2.0
		quad.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(quad)

## RACKWORK (Open Files): the faces-EXTRUDE lattice — drawer strata standing proud of the awning
## skirts (the recessed channels between them) + the green LED matrices on their fronts. The frame
## takes the body metal; the LEDs run the project terminal green, emissive.
func _add_rackwork(root: Node3D, spec: Dictionary, reserved: Array) -> void:
	var built: Dictionary = BaseShape.rack_mesh(spec, reserved)
	_add_lattice_mesh(root, "RackFrame", built.get("frame"), _tinted_tile_material("facility_metal", Color(0.40, 0.44, 0.45)))
	var led := StandardMaterial3D.new()
	led.albedo_color = Color(0.14, 0.42, 0.22)
	led.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	led.emission_enabled = true
	led.emission = Color(0.36, 0.91, 0.50)   # the terminal green
	led.emission_energy_multiplier = 2.4
	_add_lattice_mesh(root, "RackLeds", built.get("leds"), led)

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
