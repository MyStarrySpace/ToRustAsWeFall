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
const StretchGeneratorScript := preload(
	"res://scripts/generation/stretch_generator.gd"
)

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

const CH_BASE := "#"

## A Dwarf-Fortress-style HEIGHT-SLICED view: the flat data grid is single-level, but once warped onto the hub/
## spiral each cell has a real WORLD height, so slice by Y into bands and draw a top-down ASCII map per band —
## highest layer first (the base + entry), descending each loop of the spiral down to the exit. `coord_map` (the
## chunk's) warps each cell; null = flat (one layer). `nodes` overlays E/X/o. Read like DF z-levels top-to-bottom.
static func render_height_layers(grid_data: Dictionary, coord_map = null, nodes: Array = [], band_height := 1.6, max_cols := 60) -> String:
	if grid_data.is_empty():
		return "(empty grid)\n"
	var grid = GridWorldScript.from_data(grid_data)
	var risk := _risk_set(grid_data)
	var node_sym := _node_symbols(grid_data, nodes)
	# Warp every walkable cell + tag its char; collect world bounds.
	var pts: Array = []   # {w:Vector3, ch:String, rank:int}
	var minx := 1e20; var maxx := -1e20; var minz := 1e20; var maxz := -1e20; var miny := 1e20; var maxy := -1e20
	var walk_by_level := _walk_by_level(grid_data)
	var has_base: bool = coord_map != null and ("base_span" in coord_map) and float(coord_map.base_span) > 0.0
	for lvl in walk_by_level.keys():
		for cell in (walk_by_level[lvl] as Dictionary).keys():
			var flat: Vector3 = grid.grid_to_world(cell, int(lvl))
			var w: Vector3 = coord_map.to_world(flat) if coord_map != null else flat
			var ch := CH_RISK if risk.has(cell) else CH_FLOOR
			var rank := 2 if risk.has(cell) else 1
			if has_base and (flat.x - float(coord_map.s_offset)) < 0.0:
				ch = CH_BASE; rank = 3
			if node_sym.has([cell, int(lvl)]):
				ch = str(node_sym[[cell, int(lvl)]]); rank = 9
			pts.append({"w": w, "ch": ch, "rank": rank})
			minx = minf(minx, w.x); maxx = maxf(maxx, w.x); minz = minf(minz, w.z); maxz = maxf(maxz, w.z)
			miny = minf(miny, w.y); maxy = maxf(maxy, w.y)
	if pts.is_empty():
		return "(no walkable cells)\n"
	# One char per `res` world units, same for X and Z (no distortion); cap the width.
	var res: float = maxf(1.0, (maxx - minx) / float(max_cols))
	var cols := int((maxx - minx) / res) + 1
	var rows := int((maxz - minz) / res) + 1
	var band_count := maxi(1, int(ceil((maxy - miny) / maxf(0.01, band_height))))
	var out := "Height layers (%d, top y=%.1f -> bottom y=%.1f, %d x %d chars, %.1fm/char):\n" % [band_count, maxy, miny, cols, rows, res]
	# Top (highest y) first, DF-style descending.
	for b in range(band_count):
		var hi := maxy - float(b) * band_height
		var lo := hi - band_height
		# Include the very bottom in the last band.
		if b == band_count - 1:
			lo = miny - 0.001
		var grid_chars := {}   # [row,col] -> {ch, rank}
		var count := 0
		for p in pts:
			var wy: float = (p["w"] as Vector3).y
			if wy <= hi + 0.0001 and wy > lo:
				var col := clampi(int(((p["w"] as Vector3).x - minx) / res), 0, cols - 1)
				var row := clampi(int(((p["w"] as Vector3).z - minz) / res), 0, rows - 1)
				var key := [row, col]
				if not grid_chars.has(key) or int(p["rank"]) > int(grid_chars[key]["rank"]):
					grid_chars[key] = {"ch": str(p["ch"]), "rank": int(p["rank"])}
					count += 1
		out += "\n-- layer %d  y %.1f..%.1f  (%d cells) --\n" % [b, hi, lo, count]
		for row in range(rows):
			var line := ""
			for col in range(cols):
				var key := [row, col]
				line += str(grid_chars[key]["ch"]) if grid_chars.has(key) else CH_VOID
			out += line.rstrip(" ") + "\n"
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
	var authored_draft := {
		"success": true, "ok": true, "schema": "authored_ascii_v1", "id": id, "title": title, "biome": "",
		"navigation_grid": grid_data, "nodes": nodes, "routes": [], "anchors": anchors, "graybox": graybox,
		"roompieces": {}, "composition": {"chain": [], "nested": [], "teaching_chain": []},
		"headless": {"golden_path": golden, "solution_summary": {"bare_pair_solvable": true}},
		"source": {
			"generator": "ascii_authored_v1",
			"spatial_projection": "authored_flat_v1",
		},
		"palette_usage": {"flora": [], "enemies": [], "structures": []},
		"world_slot": {}, "budget": {},
	}
	return StretchGeneratorScript.finalize_authored_fixed_spec(authored_draft)

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
