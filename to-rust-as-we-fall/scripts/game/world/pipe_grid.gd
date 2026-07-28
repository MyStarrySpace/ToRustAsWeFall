class_name PipeGrid
extends RefCounted
## THE PIPE AUTO-TILER (director, 2026-07-28: "an actual pipes system ... leverage
## Godot's GridMap3D ... auto-tiling for procedural generation and modular use").
##
## One router, any backend: given the OCCUPIED CELLS of a pipe network (authored
## waypoint routes, or procedural paths later), each cell's six-neighbour mask
## resolves to a connector piece + one of the 24 orthogonal orientations:
##   1 connection -> pipe_end (bolted blind flange)
##   2 opposite   -> pipe_straight (hash-picked banded/valve variants)
##   2 orthogonal -> pipe_elbow  ("from above to left" and every other pair)
##   3            -> pipe_tee
##   4 coplanar   -> pipe_cross
## `extra_ports` declares VIRTUAL connections (a junction mouth, an off-network
## machine) so terminal cells aim their open port at the hardware they feed.
##
## Backends: `fill_gridmap` writes a real GridMap (flat scenes, procedural
## levels — pipe_tiles.meshlib via tools/build_pipe_meshlib.gd); warped scenes
## (the channels helix) apply `resolve()` results through their own per-cell
## warp instead, so both share ONE selection logic. --test-pipe-grid guards it.

const DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

## Canonical open ports per topology, in piece-local axes (must match the
## Blender authoring in ascent_pieces.py).
const PORTS := {
	"pipe_end": [Vector3i(1, 0, 0)],
	"pipe_straight": [Vector3i(1, 0, 0), Vector3i(-1, 0, 0)],
	"pipe_elbow": [Vector3i(1, 0, 0), Vector3i(0, 1, 0)],
	"pipe_tee": [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0)],
	"pipe_cross": [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)],
}

## Straight-run variation, hash-picked per cell (deterministic — no randf).
const STRAIGHT_VARIANTS := ["pipe_straight", "pipe_straight", "pipe_straight_banded",
	"pipe_straight", "pipe_straight", "pipe_straight_valve"]

## Expand axis-aligned waypoint legs into the cell list (inclusive).
static func rasterize(waypoints: Array) -> Array:
	var cells: Array = []
	var seen: Dictionary = {}
	if waypoints.is_empty():
		return cells
	var cur: Vector3i = waypoints[0]
	_push_cell(cells, seen, cur)
	for w in waypoints.slice(1):
		var to := w as Vector3i
		var d := (to - cur).sign()
		if (to - cur).abs().x + (to - cur).abs().y + (to - cur).abs().z \
				!= maxi((to - cur).abs().x, maxi((to - cur).abs().y, (to - cur).abs().z)):
			push_error("PipeGrid: waypoint leg %s -> %s is not axis-aligned" % [cur, to])
		while cur != to:
			cur += d
			_push_cell(cells, seen, cur)
	return cells

static func _push_cell(cells: Array, seen: Dictionary, c: Vector3i) -> void:
	if not seen.has(c):
		seen[c] = true
		cells.append(c)

## The router: occupied cells (+ virtual ports) -> [{cell, piece, basis}].
static func resolve(cells: Array, extra_ports: Dictionary = {}) -> Array:
	var occ: Dictionary = {}
	for c in cells:
		occ[c] = true
	var bases := _orthobases()
	var out: Array = []
	for c in cells:
		var conns: Array = []
		for d in DIRS:
			if occ.has((c as Vector3i) + (d as Vector3i)):
				conns.append(d)
		for d in extra_ports.get(c, []):
			if not conns.has(d):
				conns.append(d)
		out.append(_match_cell(c as Vector3i, conns, bases))
	return out

static func _match_cell(cell: Vector3i, conns: Array, bases: Array) -> Dictionary:
	var topo := "pipe_end"
	match conns.size():
		0, 1:
			topo = "pipe_end"
		2:
			topo = "pipe_straight" if (conns[0] as Vector3i) == -(conns[1] as Vector3i) \
				else "pipe_elbow"
		3:
			topo = "pipe_tee"
		_:
			topo = "pipe_cross"
	var piece := topo
	if topo == "pipe_straight":
		piece = STRAIGHT_VARIANTS[absi(cell.x * 7 + cell.y * 13 + cell.z * 5) \
			% STRAIGHT_VARIANTS.size()]
	var ports: Array = PORTS[topo]
	for b in bases:
		var mapped: Dictionary = {}
		for p in ports:
			var v: Vector3 = (b as Basis) * Vector3(p)
			mapped[Vector3i(roundi(v.x), roundi(v.y), roundi(v.z))] = true
		var ok := true
		for d in conns:
			if not mapped.has(d):
				ok = false
				break
		if ok and (conns.size() < 2 or mapped.size() == conns.size()):
			return {"cell": cell, "piece": piece, "basis": b}
	push_warning("PipeGrid: no orientation fits cell %s conns %s (non-coplanar 4+?)" % [cell, conns])
	return {"cell": cell, "piece": piece, "basis": Basis.IDENTITY}

## The 24 proper orthogonal rotations.
static func _orthobases() -> Array:
	var axes := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
		Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var out: Array = []
	for x in axes:
		for y in axes:
			if absf((x as Vector3).dot(y)) > 0.5:
				continue
			out.append(Basis(x, y, (x as Vector3).cross(y)))
	return out

## The GridMap backend: fills `gm` (whose mesh_library is pipe_tiles.meshlib)
## from the router's picks. Real GridMap3D — flat scenes and procgen use this.
static func fill_gridmap(gm: GridMap, cells: Array, extra_ports: Dictionary = {}) -> int:
	if gm.mesh_library == null:
		push_error("PipeGrid.fill_gridmap: GridMap has no mesh_library")
		return 0
	var name_to_item: Dictionary = {}
	for item in gm.mesh_library.get_item_list():
		name_to_item[gm.mesh_library.get_item_name(item)] = item
	var placed := 0
	for pick in resolve(cells, extra_ports):
		var item: int = int(name_to_item.get(pick["piece"], -1))
		if item < 0:
			push_warning("PipeGrid: meshlib lacks piece '%s'" % pick["piece"])
			continue
		gm.set_cell_item(pick["cell"], item,
			gm.get_orthogonal_index_from_basis(pick["basis"]))
		placed += 1
	return placed
