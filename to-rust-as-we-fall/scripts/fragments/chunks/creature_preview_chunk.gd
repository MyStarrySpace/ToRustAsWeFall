extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

## CREATURE GRAMMAR preview — a specimen gallery. Builds a small in-memory room fragment (floor,
## lights, plinths as blocked cells), then raises one SDF-meshed creature per archetype on the
## plinth row. Press N to regenerate every specimen from the next seed (each archetype rerolls
## within its body-grammar ranges). Turntable rotation is per-frame cosmetic only.

const GrammarScript := preload("res://scripts/generation/creature_grammar.gd")
const MesherScript := preload("res://scripts/generation/sdf_mesher.gd")

const PLINTH_SPACING := 3.6
const MESH_CELL := 0.095

var _seed := 1
var _turntables: Array = []
var _built_stats: Array = []

func configure_chunk(config: Dictionary) -> void:
	if config.has("seed"):
		_seed = int(config["seed"])

func is_generation_preview() -> bool:
	return true

func get_generation_seed() -> int:
	return _seed

func get_scene_title() -> String:
	return "Creature Grammar — seed %d" % _seed

func _build_chunk() -> void:
	fragment = _gallery_fragment()
	super._build_chunk()
	_turntables.clear()
	_built_stats.clear()
	var kinds: Array = GrammarScript.ARCHETYPES
	for i in range(kinds.size()):
		var body: Dictionary = GrammarScript.generate(_seed, str(kinds[i]))
		var built: Dictionary = MesherScript.build(body["prims"], MESH_CELL, body["color"])
		_built_stats.append({"archetype": body["archetype"], "verts": int(built["verts"])})
		if built["mesh"] == null:
			continue
		var root := Node3D.new()
		root.name = "Creature_%s" % str(body["archetype"])
		root.position = _plinth_pos(i, kinds.size()) + Vector3(0, 0.5, 0)
		root.scale = Vector3.ONE * 1.9   # specimen display scale — readable at gallery distance
		add_child(root)
		var mi := MeshInstance3D.new()
		mi.mesh = built["mesh"]
		root.add_child(mi)
		for g in body["glows"]:
			var gd := g as Dictionary
			var gs := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = float(gd["r"])
			sph.height = float(gd["r"]) * 2.0
			sph.radial_segments = 10
			sph.rings = 6
			gs.mesh = sph
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.05, 0.05, 0.05)
			gm.emission_enabled = true
			gm.emission = gd["color"]
			gm.emission_energy_multiplier = float(gd["energy"])
			gs.material_override = gm
			gs.position = gd["pos"]
			root.add_child(gs)
		_turntables.append(root)

func _process(delta: float) -> void:
	# cosmetic turntable — visual only, never gameplay state
	for t in _turntables:
		if is_instance_valid(t):
			(t as Node3D).rotate_y(delta * 0.35)

func get_preview_state() -> Dictionary:
	var st: Dictionary = super.get_preview_state()
	st["seed"] = _seed
	st["creatures"] = _built_stats.size()
	return st

func _plinth_pos(i: int, n: int) -> Vector3:
	return Vector3((float(i) - float(n - 1) * 0.5) * PLINTH_SPACING, 0.0, -2.4)

func _gallery_fragment() -> Fragment:
	var frag := Fragment.new()
	frag.id = "creature_gallery_%d" % _seed
	frag.title = "Creature Grammar — seed %d" % _seed
	frag.help = "Specimen row from the body grammar + SDF mesher. Press N for a new generation."
	frag.default_character = "aster"
	frag.party_ids = PackedStringArray(["aster", "peris", "endo"])
	var cs := 1.5
	var w := 16
	var h := 8
	frag.floors = [{
		"pos": Vector3(0, -0.05, 0), "size": Vector3(w * cs, 0.1, h * cs),
		"color": Color(0.10, 0.11, 0.13), "tile": "deck_metal",
	}]
	var kinds: Array = GrammarScript.ARCHETYPES
	var walls: Array[Dictionary] = []
	var plinth_cells := {}
	var origin_x := -w * cs * 0.5
	var origin_z := -h * cs * 0.5
	for i in range(kinds.size()):
		var p := _plinth_pos(i, kinds.size())
		walls.append({"pos": Vector3(p.x, 0.25, p.z), "size": Vector3(1.7, 0.5, 1.7),
			"color": Color(0.16, 0.17, 0.19)})
		var cellx := int((p.x - origin_x) / cs)
		var cellz := int((p.z - origin_z) / cs)
		for dx in range(-1, 1 + 1):
			for dz in range(-1, 1 + 1):
				if absf(p.x - (origin_x + (cellx + dx + 0.5) * cs)) < 1.2 \
						and absf(p.z - (origin_z + (cellz + dz + 0.5) * cs)) < 1.2:
					plinth_cells[Vector2i(cellx + dx, cellz + dz)] = true
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
		"aster": Vector3(-1.5, 0.5, 3.4),
		"peris": Vector3(0.0, 0.5, 3.4),
		"endo": Vector3(1.5, 0.5, 3.4),
	}
	frag.shelters = [{"min": Vector2(-4.0, 2.2), "max": Vector2(4.0, 5.6)}]
	var lights: Array[Dictionary] = []
	for i in range(kinds.size()):
		var p2 := _plinth_pos(i, kinds.size())
		lights.append({"pos": p2 + Vector3(0, 3.4, 2.0), "color": Color(0.78, 0.80, 0.84),
			"energy": 2.6, "range": 7.5})
	frag.lights = lights
	var labels: Array[Dictionary] = []
	for i in range(kinds.size()):
		var body_name := str(kinds[i]).capitalize()
		if str(kinds[i]) == "gnawer":
			body_name = "Gnawer (proposed)"
		var p3 := _plinth_pos(i, kinds.size())
		labels.append({"text": body_name, "pos": p3 + Vector3(0, 2.6, 0), "color": Color(0.62, 0.68, 0.6)})
	frag.labels = labels
	frag.params = {"stamina_field_regen": true, "creature_seed": _seed}
	frag.time_state = {"note_default": "Creature grammar gallery — N regenerates.", "routing_mode": "safe"}
	return frag
