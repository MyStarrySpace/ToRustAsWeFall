extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

## ARCHETYPE PIECE GALLERY — a walkable contact sheet of ArchetypePieceLibrary.
## Every piece in the manifest stands on its own plinth with its canonical display
## name (a dev surface, like the creature gallery — gameplay scenes never label).
## Bodies only: nothing here is interactable, by the library's honesty law.

const CatalogScript := preload("res://scripts/generation/stretch_archetype_catalog.gd")

const COLS := 6
const COL_SPACING := 3.4
const ROW_SPACING := 4.2

var _ids: Array = []

func get_scene_title() -> String:
	return "Archetype Piece Library"

func _build_chunk() -> void:
	_ids = ArchetypePieceLibrary.piece_ids()
	_ids.sort()
	fragment = _gallery_fragment()
	super._build_chunk()
	for i in range(_ids.size()):
		var id := str(_ids[i])
		var piece := ArchetypePieceLibrary.instantiate(id)
		if piece == null:
			continue
		piece.position = _plinth_pos(i) + Vector3(0.0, 0.4, 0.0)   # base ON the 0.4 plinth top
		add_child(piece)

func _plinth_pos(i: int) -> Vector3:
	var row := i / COLS
	var col := i % COLS
	return Vector3((float(col) - float(COLS - 1) * 0.5) * COL_SPACING,
		0.0, (float(row) - 1.0) * ROW_SPACING - 1.6)

func _display_name(id: String, catalog) -> String:
	for category in ["structures", "flora"]:
		var entry: Dictionary = catalog.get_content(category, id)
		if not entry.is_empty():
			return str(entry.get("display_name", id.capitalize()))
	return id.capitalize()

func _gallery_fragment() -> Fragment:
	var frag := Fragment.new()
	frag.id = "archetype_piece_gallery"
	frag.title = "Archetype Piece Library"
	frag.help = "The visual bodies for the generation content vocabulary — one plinth per piece."
	frag.default_character = "aster"
	frag.party_ids = PackedStringArray(["aster", "peris", "endo"])
	var cs := 1.5
	var w := 18
	var h := 12
	frag.floors = [{
		"pos": Vector3(0, -0.05, 0), "size": Vector3(w * cs, 0.1, h * cs),
		"color": Color(0.10, 0.11, 0.13), "tile": "deck_metal",
	}]
	var origin_x := -w * cs * 0.5
	var origin_z := -h * cs * 0.5
	var walls: Array[Dictionary] = []
	var plinth_cells := {}
	for i in range(_ids.size()):
		var p := _plinth_pos(i)
		walls.append({"pos": Vector3(p.x, 0.2, p.z), "size": Vector3(1.9, 0.4, 1.9),
			"color": Color(0.15, 0.16, 0.18)})
		var cellx := int((p.x - origin_x) / cs)
		var cellz := int((p.z - origin_z) / cs)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				if absf(p.x - (origin_x + (cellx + dx + 0.5) * cs)) < 1.3 \
						and absf(p.z - (origin_z + (cellz + dz + 0.5) * cs)) < 1.3:
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
		"aster": Vector3(-1.5, 0.5, 7.4),
		"peris": Vector3(0.0, 0.5, 7.4),
		"endo": Vector3(1.5, 0.5, 7.4),
	}
	frag.shelters = [{"min": Vector2(-4.0, 6.4), "max": Vector2(4.0, 8.6)}]
	var catalog = CatalogScript.new()
	var lights: Array[Dictionary] = []
	var labels: Array[Dictionary] = []
	for i in range(_ids.size()):
		var p := _plinth_pos(i)
		if i % 2 == 0:
			lights.append({"pos": p + Vector3(0, 3.6, 1.8), "color": Color(0.78, 0.80, 0.84),
				"energy": 2.4, "range": 8.0})
		labels.append({"text": _display_name(str(_ids[i]), catalog),
			"pos": p + Vector3(0, 2.7, 0), "color": Color(0.62, 0.68, 0.6)})
	frag.lights = lights
	frag.labels = labels
	frag.params = {"stamina_field_regen": true}
	frag.time_state = {"note_default": "Archetype piece library — bodies, never verbs.",
		"routing_mode": "safe"}
	return frag
