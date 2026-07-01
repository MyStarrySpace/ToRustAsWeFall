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
	var rows := []
	var started := false
	for line in ascii.split("\n"):
		var s := str(line)
		if s.begins_with("Level ") or s.begins_with("("):
			if started:
				break            # the next level's header ends the first block
			continue
		if s.length() == 0:
			if started:
				break            # a TRULY empty line is the separator between level blocks
			continue
		# A grid row — possibly all spaces (a void row). Keep it, so the z-rows stay aligned (dropping leading
		# void rows would shift every cell up). Grid rows are `width` chars; only "" separates blocks.
		started = true
		rows.append(s)
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
