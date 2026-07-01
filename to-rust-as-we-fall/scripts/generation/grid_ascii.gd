class_name GridAscii
extends RefCounted

## An ASCII view of a level's walkable grid — the same `.`/`#` alphabet the room-piece masks already use, extended
## for nodes + risk. It's both a debug view ("see the level as text") and a lossless interchange for a level
## builder: render(grid) -> text, parse(text) -> grid, and render(parse(text)) round-trips the walkable/risk set.
##
## Alphabet (per cell):
##   ' '  void / not walkable
##   '.'  walkable floor
##   '~'  walkable but RISKY (a risky/shortcut route cell)
##   'E'  entry node          'X'  exit shelter node          'o'  any other node
## Multi-level grids print one labelled block per level (stacked floors), rows are +Z downward.

const GridWorldScript := preload("res://scripts/game/world/grid_world.gd")

const CH_VOID := " "
const CH_FLOOR := "."
const CH_RISK := "~"
const CH_ENTRY := "E"
const CH_EXIT := "X"
const CH_NODE := "o"

static func render_spec(spec: Dictionary) -> String:
	return render(spec.get("navigation_grid", {}), spec.get("nodes", []))

## Render a `unified_grid_v1` grid (+ optional nodes for the E/X/o overlay) as ASCII.
static func render(grid_data: Dictionary, nodes: Array = []) -> String:
	if grid_data.is_empty():
		return "(empty grid)\n"
	var w := int(grid_data.get("width", 0))
	var h := int(grid_data.get("height", 0))
	var level_count: int = maxi(1, int(grid_data.get("level_count", 1)))
	var walk_by_level := _walk_by_level(grid_data)
	var risk := _risk_set(grid_data)
	var node_sym := _node_symbols(grid_data, nodes)
	var out := ""
	for lvl in range(level_count):
		if not walk_by_level.has(lvl):
			continue
		if level_count > 1:
			out += "Level %d:\n" % lvl
		var cells: Dictionary = walk_by_level[lvl]
		for z in range(h):
			var row := ""
			for x in range(w):
				var cell := Vector2i(x, z)
				var ch := CH_VOID
				if cells.has(cell):
					ch = CH_RISK if risk.has(cell) else CH_FLOOR
					# Node overlays draw ONLY on real walkable cells, so the ASCII's floor set stays exactly the
					# grid's walkable set (a lossless interchange — a node never invents floor on a void cell).
					if node_sym.has([cell, lvl]):
						ch = str(node_sym[[cell, lvl]])
				row += ch
			out += row + "\n"
		if level_count > 1 and lvl < level_count - 1:
			out += "\n"
	return out

## Parse an ASCII block (single level, or the first level) back into a partial `unified_grid_v1` grid_data:
## walkable_cells + risk_cell_list + width/height + a default origin/cell_size. Node identity is not preserved
## (E/X/o become plain walkable); a builder layers nodes on separately. render->parse->render is stable.
static func parse(ascii: String) -> Dictionary:
	var rows := _first_block_rows(ascii)
	var walkable := []
	var risk := []
	var w := 0
	for z in range(rows.size()):
		var line: String = rows[z]
		w = maxi(w, line.length())
		for x in range(line.length()):
			var ch := line[x]
			if ch == CH_VOID:
				continue
			walkable.append([x, z])
			if ch == CH_RISK:
				risk.append({"cell": [x, z], "penalty": 1.0, "recoverable": true})
	var risk_only := []
	for r in risk:
		risk_only.append(r)
	return {
		"contract_id": GridWorldScript.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.45, 0.0],
		"cell_size": 1.0,
		"width": w,
		"height": rows.size(),
		"walkable_cells": walkable,
		"level_cells": [],
		"risk_cell_list": risk_only,
		"links": [],
		"route_cells": {},
		"level_count": 1,
		"level_height": 0.72,
		"entry_anchor": "entry",
		"exit_anchor": "exit_shelter",
	}

## The rows of the FIRST level block (headers + the "" separator stripped, void rows kept for z-alignment).
static func _first_block_rows(ascii: String) -> Array:
	var rows := []
	var started := false
	for line in ascii.split("\n"):
		var s := str(line)
		if s.begins_with("Level ") or s.begins_with("("):
			if started:
				break
			continue
		if s.length() == 0:
			if started:
				break
			continue
		started = true
		rows.append(s)
	return rows

## Build a MINIMAL playable generated-stretch spec from an authored ASCII map: the tiled floor + grid come from
## the ASCII, and E/X/o become entry / exit / interior nodes. The generated_stretch chunk renders + plays it
## (it uses the provided unified_grid_v1 navigation_grid as-is). Single-level (an authored map is one floor).
static func spec_from_ascii(ascii: String, title := "Authored Level", id := "authored_level") -> Dictionary:
	var grid_data := parse(ascii)
	var grid = GridWorldScript.from_data(grid_data)
	var rows := _first_block_rows(ascii)
	var node_cells := []   # {cell:[x,z], id, role}
	var interior := 0
	for z in range(rows.size()):
		var line: String = rows[z]
		for x in range(line.length()):
			var ch := line[x]
			if ch == CH_ENTRY:
				node_cells.append({"cell": [x, z], "id": "entry", "role": "boundary"})
			elif ch == CH_EXIT:
				node_cells.append({"cell": [x, z], "id": "exit_shelter", "role": "shelter_arrival"})
			elif ch == CH_NODE:
				node_cells.append({"cell": [x, z], "id": "node_%02d" % interior, "role": "mixed"})
				interior += 1
	# Guarantee an entry + exit: if the author didn't mark them, use the first / last walkable cell.
	var walkable: Array = grid_data.get("walkable_cells", [])
	if not _has_node(node_cells, "entry") and not walkable.is_empty():
		node_cells.push_front({"cell": walkable[0], "id": "entry", "role": "boundary"})
	if not _has_node(node_cells, "exit_shelter") and not walkable.is_empty():
		node_cells.append({"cell": walkable[walkable.size() - 1], "id": "exit_shelter", "role": "shelter_arrival"})

	var nodes := []
	var golden := []
	for nc in node_cells:
		var cell := Vector2i(int(nc.cell[0]), int(nc.cell[1]))
		var wp: Vector3 = grid.grid_to_world(cell, 0)
		nodes.append({
			"id": nc.id, "role": nc.role, "title": String(nc.id).capitalize().replace("_", " "),
			"position": [wp.x, wp.y, wp.z], "elevation_index": 0, "surface_y": wp.y,
			"footprint": [1.4, 0.2, 1.4], "approach_position": [wp.x, wp.y, wp.z],
			"content_placements": [], "flora": [], "enemies": [], "structures": [],
			"approaches": [], "stage": 1, "optional": false, "variant": "",
		})
		golden.append(nc.id)

	var origin: Array = grid_data.get("origin", [0.0, 0.45, 0.0])
	var cs := float(grid_data.get("cell_size", 1.0))
	var gw := int(grid_data.get("width", 0)) * cs
	var gh := int(grid_data.get("height", 0)) * cs
	var center := [float(origin[0]) + gw * 0.5, float(origin[1]), float(origin[2]) + gh * 0.5]
	var graybox := {
		"contract_id": "generated_stretch_graybox_v1",
		"bounds": {"center": center, "size": [gw, 3.0, gh], "min": [float(origin[0]), float(origin[1]), float(origin[2])]},
		"layout_engine": "ascii",
	}
	var entry_pos: Array = _node_pos(nodes, "entry")
	var anchors := {
		"aster": entry_pos, "peris": [entry_pos[0] + 0.4, entry_pos[1], entry_pos[2] + 0.4],
		"endo": [entry_pos[0] - 0.4, entry_pos[1], entry_pos[2] - 0.4],
	}
	for n in nodes:
		anchors[str(n.id)] = n.position
	return {
		"success": true, "ok": true, "schema": "authored_ascii_v1", "id": id, "title": title, "biome": "",
		"navigation_grid": grid_data, "nodes": nodes, "routes": [], "anchors": anchors, "graybox": graybox,
		"roompieces": {}, "composition": {"chain": [], "nested": [], "teaching_chain": []},
		"headless": {"golden_path": golden, "solution_summary": {"bare_pair_solvable": true}},
		"source": {"generator": "ascii_authored_v1"}, "palette_usage": {"flora": [], "enemies": [], "structures": []},
		"world_slot": {}, "budget": {},
	}

static func _has_node(node_cells: Array, id: String) -> bool:
	for nc in node_cells:
		if str(nc.get("id", "")) == id:
			return true
	return false

static func _node_pos(nodes: Array, id: String) -> Array:
	for n in nodes:
		if str(n.get("id", "")) == id:
			return n.get("position", [0.0, 0.45, 0.0])
	return [0.0, 0.45, 0.0]

# --- helpers ---------------------------------------------------------------------------------------------------

static func _walk_by_level(grid_data: Dictionary) -> Dictionary:
	var out := {}
	var lc: Array = grid_data.get("level_cells", [])
	if not lc.is_empty():
		for e in lc:
			if e is Dictionary:
				out[int(e.get("level", 0))] = _cellset(e.get("cells", []))
	else:
		out[0] = _cellset(grid_data.get("walkable_cells", []))
	return out

static func _cellset(cells: Array) -> Dictionary:
	var s := {}
	for c in cells:
		s[Vector2i(int((c as Array)[0]), int((c as Array)[1]))] = true
	return s

static func _risk_set(grid_data: Dictionary) -> Dictionary:
	var s := {}
	for r in grid_data.get("risk_cell_list", []):
		if r is Dictionary and r.has("cell"):
			s[Vector2i(int((r.cell as Array)[0]), int((r.cell as Array)[1]))] = true
	return s

static func _node_symbols(grid_data: Dictionary, nodes: Array) -> Dictionary:
	var out := {}
	if nodes.is_empty():
		return out
	var grid = GridWorldScript.from_data(grid_data)
	for n in nodes:
		if not (n is Dictionary):
			continue
		var pos: Array = (n as Dictionary).get("position", [0, 0, 0])
		var cell: Vector2i = grid.world_to_grid(Vector3(float(pos[0]), float(pos[1]), float(pos[2])))
		var lvl := int((n as Dictionary).get("elevation_index", 0))
		var id := str((n as Dictionary).get("id", ""))
		var ch := CH_NODE
		if id == "entry":
			ch = CH_ENTRY
		elif id == "exit_shelter":
			ch = CH_EXIT
		out[[cell, lvl]] = ch
	return out
